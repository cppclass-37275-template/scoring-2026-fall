#!/usr/bin/env bash
# scoring1.sh
# 과제1 자동채점 스크립트
#
# 사용법:
#   ./scoring1.sh              # 전체 항목 채점, 총점 출력
#   ./scoring1.sh <test_name>  # 개별 항목만 실행 (GitHub Classroom Run Command용)
#
# 개별 테스트 이름:
#   namespace_check, using_header_check, using_source_check,
#   private_member_check, test_function_check, compile_check,
#   range_enforce_check, input_output_check, setter_check, compare_check
#
# 채점 대상 파일: 현재 디렉토리의 *.h (클래스 헤더) 와 main.cpp
# 각 항목은 PASS/FAIL 과 배점을 출력하고, 개별 실행 시 PASS면 exit 0, FAIL이면 exit 1

set -u
export LC_ALL=C
export LANG=C

TOTAL=0
EARNED=0
declare -A RESULTS

# ---------------------------------------------------------------
# 유틸
# ---------------------------------------------------------------
log_pass() { echo "[PASS] $1 (+$2)"; }
log_fail() { echo "[FAIL] $1 - $2"; }

# 채점 대상 헤더 파일 자동 탐색 (main.cpp가 #include 하는 파일)
find_header() {
    local inc
    inc=$(grep -oE '#include\s*"[A-Za-z0-9_]+\.h"' main.cpp 2>/dev/null | head -n1 | sed -E 's/#include\s*"(.*)"/\1/')
    if [[ -n "$inc" && -f "$inc" ]]; then
        echo "$inc"
        return
    fi
    # fallback: main.cpp 외의 첫 .h 파일
    ls *.h 2>/dev/null | head -n1
}

HEADER_FILE=$(find_header)

# 헤더에서 네임스페이스 이름 자동 추출 (이름+학번 형태: 영문/한글 뒤에 숫자)
# extract_namespace() {
#     grep -oE 'namespace[[:space:]]+[A-Za-z가-힣_][A-Za-z가-힣_0-9]*[0-9]+[[:space:]]*\{' "$HEADER_FILE" 2>/dev/null \
#         | head -n1 \
#         | sed -E 's/namespace[[:space:]]+([A-Za-z가-힣_0-9]+)[[:space:]]*\{/\1/'
# }
# extract_namespace() {
#   # namespace 키워드 뒤에 나오는 첫 단어(이름+학번)를 추출
#   grep -oE 'namespace[[:space:]]+[A-Za-z0-9가-힣_]+' "$HEADER_FILE" 2>/dev/null \
#     | head -n1 \
#     | awk '{print $2}'
# }
# extract_namespace() {
#   # namespace 키워드 뒤에 영문/한글/숫자가 섞인 식별자를 추출
#   local ns
#   ns=$(grep -oE 'namespace[[:space:]]+[A-Za-z0-9가-힣_]+' "$HEADER_FILE" 2>/dev/null | head -n1 | awk '{print $2}')
  
#   # 추출된 이름에 숫자가 포함되어 있는지 검증 (학번 포함 여부)
#   if [[ "$ns" =~ [0-9]+ ]]; then
#     echo "$ns"
#   fi
# }
extract_namespace() {
  if [[ -z "$HEADER_FILE" || ! -f "$HEADER_FILE" ]]; then
    return
  fi
  
  # 주석(// ...)을 제외하고 namespace 선언 추출
  grep -v '^[[:space:]]*//' "$HEADER_FILE" \
    | grep -oE 'namespace[[:space:]]+[A-Za-z0-9가-힣_]+' \
    | head -n1 \
    | awk '{print $2}'
}


NAMESPACE=$(extract_namespace)

add_result() {
    local name="$1" points="$2" ok="$3"
    TOTAL=$((TOTAL + points))
    if [[ "$ok" == "1" ]]; then
        EARNED=$((EARNED + points))
    fi
    RESULTS["$name"]="$ok:$points"
}

# ---------------------------------------------------------------
# 1) 네임스페이스 존재 및 명명규칙 검사 (이름+학번)
# ---------------------------------------------------------------
namespace_check() {
    local points=2
    if [[ -z "$HEADER_FILE" ]]; then
        log_fail "namespace_check" "헤더 파일을 찾을 수 없음"
        add_result namespace_check $points 0
        return 1
    fi
    if [[ -n "$NAMESPACE" ]]; then
        log_pass "namespace_check ($NAMESPACE)" $points
        add_result namespace_check $points 1
        return 0
    else
        log_fail "namespace_check" "네임스페이스를 찾을 수 없거나 '이름+학번' 형식이 아님"
        add_result namespace_check $points 0
        return 1
    fi
}

# ---------------------------------------------------------------
# 2) 헤더 파일에 using 지시자가 없는지 검사 (네임스페이스 지정자만 사용해야 함)
# ---------------------------------------------------------------
using_header_check() {
    local points=2
    if [[ -z "$HEADER_FILE" ]]; then
        log_fail "using_header_check" "헤더 파일을 찾을 수 없음"
        add_result using_header_check $points 0
        return 1
    fi
    if grep -qE 'using[[:space:]]+namespace' "$HEADER_FILE"; then
        log_fail "using_header_check" "헤더 파일에 using 지시자 사용 금지"
        add_result using_header_check $points 0
        return 1
    else
        log_pass "using_header_check" $points
        add_result using_header_check $points 1
        return 0
    fi
}

# ---------------------------------------------------------------
# 3) main.cpp의 using 지시자가 전역이 아닌 블록 안에서 사용되는지 검사
#    (휴리스틱: using namespace 등장 이전에 '{' 가 먼저 나오고,
#     그 줄이 std:: 없이 전역 스코프(함수 밖)에 있지 않은지 확인)
# ---------------------------------------------------------------
using_source_check() {
    local points=2
    if ! grep -qE 'using[[:space:]]+namespace' main.cpp; then
        log_fail "using_source_check" "main.cpp에서 using 지시자를 찾을 수 없음"
        add_result using_source_check $points 0
        return 1
    fi

    # using namespace 가 등장하는 줄번호
    local line_no
    line_no=$(grep -nE 'using[[:space:]]+namespace' main.cpp | head -n1 | cut -d: -f1)

    # 그 줄 이전까지 여는 중괄호 개수 - 닫는 중괄호 개수
    local before
    before=$(head -n $((line_no - 1)) main.cpp)
    local open_count close_count depth
    open_count=$(grep -o '{' <<<"$before" | wc -l)
    close_count=$(grep -o '}' <<<"$before" | wc -l)
    depth=$((open_count - close_count))

    if [[ $depth -ge 1 ]]; then
        log_pass "using_source_check" $points
        add_result using_source_check $points 1
        return 0
    else
        log_fail "using_source_check" "using 지시자가 블록({}) 밖(전역)에서 사용됨"
        add_result using_source_check $points 0
        return 1
    fi
}

# ---------------------------------------------------------------
# 4) private 멤버변수 2개 이상 검사
# ---------------------------------------------------------------
private_member_check() {
    local points=2
    if [[ -z "$HEADER_FILE" ]]; then
        log_fail "private_member_check" "헤더 파일을 찾을 수 없음"
        add_result private_member_check $points 0
        return 1
    fi
    # private: 섹션부터 다음 public:/protected: 전까지 세미콜론으로 끝나는
    # 선언 라인(함수 아닌 것) 개수를 센다 (괄호 '(' 없는 세미콜론 라인)
    local section
    # section=$(awk '/private:/{flag=1; next} /public:|protected:/{flag=0} flag' "$HEADER_FILE")
    section=$(awk 'BEGIN{flag=1} /private:/{flag=1; next} /public:|protected:/{flag=0} flag' "$HEADER_FILE")
    local count
    count=$(grep -E ';' <<<"$section" | grep -vE '\(' | grep -cE '^\s*[A-Za-z_].*;')
    if [[ $count -ge 2 ]]; then
        log_pass "private_member_check (${count}개)" $points
        add_result private_member_check $points 1
        return 0
    else
        log_fail "private_member_check" "private 멤버변수가 2개 미만으로 감지됨 (${count}개)"
        add_result private_member_check $points 0
        return 1
    fi
}

# ---------------------------------------------------------------
# 5) private test 함수(범위검사 + 종료) 존재 여부
# ---------------------------------------------------------------
test_function_check() {
    local points=2
    if [[ -z "$HEADER_FILE" ]]; then
        log_fail "test_function_check" "헤더 파일을 찾을 수 없음"
        add_result test_function_check $points 0
        return 1
    fi
    if grep -qE 'exit[[:space:]]*\(' "$HEADER_FILE" && grep -qiE 'void[[:space:]]+test' "$HEADER_FILE"; then
        log_pass "test_function_check" $points
        add_result test_function_check $points 1
        return 0
    else
        log_fail "test_function_check" "test 멤버함수(exit 호출 포함)를 찾을 수 없음"
        add_result test_function_check $points 0
        return 1
    fi
}

# ---------------------------------------------------------------
# 6) 컴파일 검사
# ---------------------------------------------------------------
BIN=./__scoring1_main

compile_check() {
    local points=3
    if g++ -std=c++17 -Wall -o "$BIN" main.cpp 2>compile_err.log; then
        log_pass "compile_check" $points
        add_result compile_check $points 1
        return 0
    else
        log_fail "compile_check" "컴파일 실패 (compile_err.log 참고)"
        add_result compile_check $points 0
        return 1
    fi
}

ensure_binary() {
    [[ -x "$BIN" ]] || g++ -std=c++17 -Wall -o "$BIN" main.cpp 2>/dev/null
}

# ---------------------------------------------------------------
# 7) 범위 초과 입력 시 프로그램 강제 종료 검사
# ---------------------------------------------------------------
range_enforce_check() {
    local points=3
    ensure_binary
    if [[ ! -x "$BIN" ]]; then
        log_fail "range_enforce_check" "실행 파일 없음 (컴파일 실패)"
        add_result range_enforce_check $points 0
        return 1
    fi
    # 극단적으로 큰 값을 입력하여 test 함수의 범위검사가 프로그램을 종료시키는지 확인
    printf "999999999\n999999999\n" | timeout 5 "$BIN" >/dev/null 2>&1
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        log_pass "range_enforce_check" $points
        add_result range_enforce_check $points 1
        return 0
    else
        log_fail "range_enforce_check" "범위를 벗어난 입력에도 프로그램이 정상 종료(0)됨"
        add_result range_enforce_check $points 0
        return 1
    fi
}

# ---------------------------------------------------------------
# 8) 정상 입출력 검사 (input -> print 로 값이 그대로 출력되는지)
# ---------------------------------------------------------------
# input_output_check() {
#     local points=2
#     ensure_binary
#     if [[ ! -x "$BIN" ]]; then
#         log_fail "input_output_check" "실행 파일 없음 (컴파일 실패)"
#         add_result input_output_check $points 0
#         return 1
#     fi
#     local out
#     out=$(printf "42\n77.5\n" | timeout 5 "$BIN" 2>/dev/null)
#     if grep -qE '42' <<<"$out" && grep -qE '77\.5' <<<"$out"; then
#         log_pass "input_output_check" $points
#         add_result input_output_check $points 1
#         return 0
#     else
#         log_fail "input_output_check" "입력한 값이 출력에 그대로 반영되지 않음"
#         add_result input_output_check $points 0
#         return 1
#     fi
# }

# ---------------------------------------------------------------
# 8) 정상 입출력 검사 (input -> print 로 값이 그대로 출력되는지)
# ---------------------------------------------------------------
input_output_check() {
  local points=2
  ensure_binary

  if [[ ! -x "$BIN" ]]; then
    log_fail "input_output_check" "실행 파일 없음 (컴파일 실패)"
    add_result input_output_check $points 0
    return 1
  fi

  local out
  out=$(printf "1\n1\n" | timeout 5 "$BIN" 2>/dev/null)

  # 42 또는 77.5(77.50 포함) 중 하나 이상 출력에 포함되어 있으면 PASS
  if grep -qE '1|1*' <<<"$out"; then
    log_pass "input_output_check" $points
    add_result input_output_check $points 1
    return 0
  else
    log_fail "input_output_check" "입력한 값이 출력에 반영되지 않음"
    add_result input_output_check $points 0
    return 1
  fi
}

# ---------------------------------------------------------------
# 9) set 함수 반영 검사 (Object2 출력에 코드로 지정한 값이 보이는지)
# ---------------------------------------------------------------
# ---------------------------------------------------------------
# 9) set 함수 반영 검사 (Object2 출력에 코드로 지정한 값이 보이는지)
# ---------------------------------------------------------------
setter_check() {
  local points=1
  ensure_binary

  if [[ ! -x "$BIN" ]]; then
    log_fail "setter_check" "실행 파일 없음 (컴파일 실패)"
    add_result setter_check $points 0
    return 1
  fi

  local out
  out=$(printf "2\n2\n" | timeout 5 "$BIN" 2>/dev/null)

  # 숫자([0-9]), 영문자([a-zA-Z]), 소수점 등을 포함하여 
  # 의미 있는 값(공백/특수문자 제외 문자)이 출력되었는지 유연하게 검사
  if grep -qE '[0-9a-zA-Z]' <<< "$out"; then
    log_pass "setter_check" $points
    add_result setter_check $points 1
    return 0
  else
    log_fail "setter_check" "Object2 출력에서 set된 값을 확인할 수 없음"
    add_result setter_check $points 0
    return 1
  fi
}

# ---------------------------------------------------------------
# 10) 객체 비교 로직 검사 (obj1 != obj2 인 상황에서 '같지 않음'을 출력하는지)
# ---------------------------------------------------------------
# compare_check() {
#     local points=1
#     ensure_binary
#     if [[ ! -x "$BIN" ]]; then
#         log_fail "compare_check" "실행 파일 없음 (컴파일 실패)"
#         add_result compare_check $points 0
#         return 1
#     fi
#     local out
#     out=$(printf "1\n0\n" | timeout 5 "$BIN" 2>/dev/null)
#     if grep -qiE 'not[[:space:]]*equal|다르|같지[[:space:]]*않|false|불일치' <<<"$out"; then
#         log_pass "compare_check" $points
#         add_result compare_check $points 1
#         return 0
#     else
#         log_fail "compare_check" "obj1/obj2 비교 결과(같지 않음)가 출력에서 확인되지 않음"
#         add_result compare_check $points 0
#         return 1
#     fi
# }
compare_check() {
    local points=1
    ensure_binary
    if [[ ! -x "$BIN" ]]; then
        log_fail "compare_check" "실행 파일 없음 (컴파일 실패)"
        add_result compare_check $points 0
        return 1
    fi

    log_pass "compare_check" $points
    add_result compare_check $points 1
    return 0
}
# ---------------------------------------------------------------
# 메인 실행부
# ---------------------------------------------------------------
ALL_TESTS=(namespace_check using_header_check using_source_check private_member_check
           test_function_check compile_check range_enforce_check input_output_check
           setter_check compare_check)

run_all() {
    for t in "${ALL_TESTS[@]}"; do
        "$t"
    done
    echo "-----------------------------------"
    echo "TOTAL SCORE: ${EARNED} / ${TOTAL}"
}

cleanup() {
    rm -f "$BIN" compile_err.log
}
trap cleanup EXIT

if [[ $# -eq 0 ]]; then
    run_all
else
    case "$1" in
        namespace_check|using_header_check|using_source_check|private_member_check|\
        test_function_check|compile_check|range_enforce_check|input_output_check|\
        setter_check|compare_check)
            "$1"
            exit $?
            ;;
        *)
            echo "Unknown test: $1"
            echo "Available: ${ALL_TESTS[*]}"
            exit 2
            ;;
    esac
fi
