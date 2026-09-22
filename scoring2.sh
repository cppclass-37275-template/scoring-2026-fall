#!/bin/bash
# ==============================================================================
# scoring2.sh
# 클래스1/클래스2 연산자 오버로딩 과제 자동채점 스크립트 (총 20점)
#
# 사용법:
#   ./scoring2.sh                → 모든 체크를 순서대로 실행하고 총점 요약 출력
#   ./scoring2.sh all            → 위와 동일
#   ./scoring2.sh <check_name>   → 개별 체크 1개만 실행 (GitHub Classroom에서 사용)
#
# 대상 파일 (현재 디렉토리 기준):
#   클래스1을 정의하는 헤더 (파일명은 학생마다 다름, 자동 탐지)
#   클래스2를 정의하는 헤더 (파일명은 학생마다 다름, 자동 탐지)
#   main.cpp   - 테스트 코드 (없으면 디렉토리의 다른 .cpp 파일로 대체 탐지)
#
# 클래스1/클래스2는 "문제에서 쓰인 일반 명칭"일 뿐, 실제 파일명·클래스명은
# 학생마다 자유롭게 지을 수 있으므로, 아래 resolve_files()가 헤더 파일들을
# 스캔해서 어떤 파일이 클래스1(증가연산자를 갖는 쪽)이고 어떤 파일이
# 클래스2(클래스1형 객체를 멤버로 갖는 쪽)인지 자동으로 판별합니다.
#
# 성공 시: "PASS: <설명>" 출력 후 exit 0
# 실패 시: "FAIL: <이유>" 출력 후 exit 1
#
# 환경변수:
#   NUM_FIELDS  - 런타임 입력 테스트에 사용할 클래스1 멤버변수 개수 (기본값 2)
# ==============================================================================

set -u

H1=""
H2=""
MAIN=""
NUM_FIELDS="${NUM_FIELDS:-2}"

# ------------------------------------------------------------------------
# 유틸리티
# ------------------------------------------------------------------------
fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; exit 0; }

require_files() {
    for f in "$@"; do
        if [ -z "$f" ]; then
            fail "클래스1/클래스2 헤더 파일을 자동으로 찾지 못했습니다 (.h 파일이 2개 이상 있어야 합니다)"
        fi
        [ -f "$f" ] || fail "필요한 파일이 없습니다: $f"
    done
}

# 주석(//, /* */) 제거. 문자열 리터럴 안의 // 같은 예외 케이스는 고려하지 않음(일반적인 과제 코드 기준으로 충분).
strip_comments() {
    sed -e 's#//.*##' "$1" | sed -e ':a;N;$!ba;s#/\*[^*]*\*\+\([^/*][^*]*\*\+\)*/##g'
}

# 클래스1.h 에서 네임스페이스 이름 탐지 (std 제외, 첫 번째 매치)
detect_namespace() {
    # grep -oP 'namespace\s+\K[A-Za-z_][A-Za-z0-9_]*(?=\s*\{)' "$H1" 2>/dev/null | grep -v '^std$' | head -1
    grep -oE 'namespace[[:space:]]+[A-Za-z가-힣_][A-Za-z가-힣_0-9]*[0-9]+[[:space:]]*\{' "$HEADER_FILE" 2>/dev/null \
        | head -n1 \
        | sed -E 's/namespace[[:space:]]+([A-Za-z가-힣_0-9]+)[[:space:]]*\{/\1/'
}

# 헤더파일에서 class 이름 탐지
detect_class_name() {
    grep -oP 'class\s+\K\w+' "$1" 2>/dev/null | head -1
}

# 현재 디렉토리의 .h 파일들을 스캔해서 클래스1/클래스2 헤더와 main.cpp를
# 자동으로 판별하여 전역변수 H1, H2, MAIN 을 채운다. 파일명/클래스명이
# 학생마다 다르므로 이름이 아니라 "구조적 특징"으로 구분한다:
#   - 클래스1 헤더: operator++ (전위/후위 증가연산자)를 갖고 있는 헤더
#   - 클래스2 헤더: 클래스1의 클래스 타입을 멤버변수로 갖는 헤더
resolve_files() {
    # main.cpp (없으면 디렉토리의 유일한/첫 .cpp 파일로 대체)
    if [ -f "main.cpp" ]; then
        MAIN="main.cpp"
    else
        MAIN=$(ls *.cpp 2>/dev/null | head -1)
    fi

    local hfiles=()
    while IFS= read -r -d '' f; do
        hfiles+=("$f")
    done < <(find . -maxdepth 1 -type f \( -iname '*.h' -o -iname '*.hpp' \) -print0 2>/dev/null)

    if [ "${#hfiles[@]}" -lt 2 ]; then
        H1="${hfiles[0]:-}"
        H2=""
        return
    fi

    local f stripped c1="" c1class=""
    for f in "${hfiles[@]}"; do
        stripped=$(strip_comments "$f")
        if echo "$stripped" | grep -qP 'operator\s*\+\+'; then
            c1="$f"
            break
        fi
    done

    # operator++ 로 못 찾았으면, friend 입력/출력연산자를 갖는 헤더를 클래스1로 간주
    if [ -z "$c1" ]; then
        for f in "${hfiles[@]}"; do
            stripped=$(strip_comments "$f")
            if echo "$stripped" | grep -qP 'friend\b[^;{]*operator\s*(>>|<<)'; then
                c1="$f"
                break
            fi
        done
    fi

    # 그래도 못 찾았으면 첫 번째 헤더를 임시로 클래스1로 둔다 (이후 개별 체크가 실패 사유를 알려줌)
    [ -z "$c1" ] && c1="${hfiles[0]}"

    c1class=$(detect_class_name "$c1")

    local c2=""
    if [ -n "$c1class" ]; then
        for f in "${hfiles[@]}"; do
            [ "$f" = "$c1" ] && continue
            stripped=$(strip_comments "$f")
            if echo "$stripped" | grep -qP "\b${c1class}\b\s+\w+\s*;"; then
                c2="$f"
                break
            fi
        done
    fi

    # 멤버 타입으로도 못 찾았으면, 클래스1이 아닌 나머지 헤더 중 첫 번째를 클래스2로 간주
    if [ -z "$c2" ]; then
        for f in "${hfiles[@]}"; do
            if [ "$f" != "$c1" ]; then
                c2="$f"
                break
            fi
        done
    fi

    H1="$c1"
    H2="$c2"
}

compile_or_fail() {
    # 주의: 이 함수는 항상 $(...)(명령치환/서브셸) 안에서 호출되므로
    # 내부에서 fail()(exit)을 쓰면 상위 스크립트로 종료가 전파되지 않는다.
    # 그래서 실패 시 "COMPILE_ERROR::<메시지>"를 표준출력으로 내보내고
    # 0이 아닌 종료코드를 반환하며, 호출하는 쪽에서 그 종료코드를 보고
    # 직접 fail()을 호출하도록 한다.
    if [ -z "$H1" ] || [ ! -f "$H1" ] || [ -z "$H2" ] || [ ! -f "$H2" ] || [ -z "$MAIN" ] || [ ! -f "$MAIN" ]; then
        echo "COMPILE_ERROR::필요한 파일을 찾을 수 없습니다 (헤더 2개 + main.cpp 필요)"
        return 1
    fi
    local bin="/tmp/scoring2_bin_$$"
    local err
    err=$(g++ -std=c++17 -Wall -o "$bin" "$MAIN" 2>&1)
    if [ $? -ne 0 ]; then
        echo "COMPILE_ERROR::$(echo "$err" | head -5 | tr '\n' ' ')"
        return 1
    fi
    echo "$bin"
    return 0
}

# NUM_FIELDS * 2 개의 숫자를 입력으로 생성 (객체 2개분). 인자로 넘긴 값들을 순환 사용.
gen_input() {
    local vals=("$@")
    local n=$((NUM_FIELDS * 2))
    local out=""
    for ((i = 0; i < n; i++)); do
        out+="${vals[$((i % ${#vals[@]}))]} "
    done
    echo "$out"
}

# ------------------------------------------------------------------------
# 정적 구조 체크 (1점씩)
# ------------------------------------------------------------------------

check_namespace() {
    require_files "$H1" "$H2"
    local ns
    ns=$(detect_namespace)
    [ -z "$ns" ] && fail "네임스페이스를 찾을 수 없습니다 (이름+학번 형식 필요)"
    echo "$ns" | grep -qP '^[A-Za-z가-힣]+[0-9]{4,}$' \
        || fail "네임스페이스 이름이 '이름+학번' 형식이 아닙니다: $ns"
    grep -q "namespace[[:space:]]\+$ns" "$H1" || fail "클래스1.h 에 네임스페이스가 적용되지 않았습니다"
    grep -q "namespace[[:space:]]\+$ns" "$H2" || fail "클래스2.h 에 네임스페이스가 적용되지 않았습니다"
    pass "네임스페이스 '$ns' 확인됨"
}

check_using_header() {
    require_files "$H1" "$H2"
    for f in "$H1" "$H2"; do
        local stripped
        stripped=$(strip_comments "$f")
        echo "$stripped" | grep -qP '\busing\s+' && fail "$f 에서 using 지시자/선언이 발견되었습니다 (주석 제외)"
    done
    pass "헤더파일에 using 지시자/선언 없음 확인"
}

check_class1_constructor() {
    require_files "$H1"
    local stripped cls
    stripped=$(strip_comments "$H1")
    cls=$(detect_class_name "$H1")
    [ -z "$cls" ] && fail "클래스1을 찾을 수 없습니다"
    echo "$stripped" | grep -qP "(?<!~)\b${cls}\s*\([^)]*\)\s*(:|\{)" \
        || fail "클래스1 생성자를 찾을 수 없습니다 (클래스: $cls)"
    pass "클래스1 생성자 확인됨 (클래스: $cls)"
}

check_class1_const() {
    require_files "$H1"
    local stripped get_lines non_const
    stripped=$(strip_comments "$H1")
    echo "$stripped" | grep -qP '\bprint\s*\([^)]*\)\s*const' \
        || fail "print 함수가 const 멤버함수로 정의되지 않았습니다"
    get_lines=$(echo "$stripped" | grep -oP '\w[\w:<>&\*]*\s+get\w*\s*\([^)]*\)\s*(const)?')
    [ -z "$get_lines" ] && fail "get 접근함수를 찾을 수 없습니다"
    non_const=$(echo "$get_lines" | grep -vP 'const\s*$')
    [ -n "$non_const" ] && fail "const로 정의되지 않은 get 함수가 있습니다: $(echo "$non_const" | head -1)"
    pass "print/get 함수의 const 지정 확인됨"
}

check_class1_prefix_increment() {
    require_files "$H1"
    local stripped
    stripped=$(strip_comments "$H1")
    echo "$stripped" | grep -qP 'operator\s*\+\+\s*\(\s*\)' \
        || fail "전위증가연산자(operator++())를 찾을 수 없습니다"
    pass "전위증가연산자 확인됨"
}

check_class1_postfix_increment() {
    require_files "$H1"
    local stripped
    stripped=$(strip_comments "$H1")
    echo "$stripped" | grep -qP 'operator\s*\+\+\s*\(\s*int\s*\)' \
        || fail "후위증가연산자(operator++(int))를 찾을 수 없습니다"
    pass "후위증가연산자 확인됨"
}

check_class1_friend_input() {
    require_files "$H1"
    local stripped
    stripped=$(strip_comments "$H1")
    echo "$stripped" | grep -qP 'friend\b[^;{]*operator\s*>>' \
        || fail "friend 입력연산자(operator>>)를 찾을 수 없습니다"
    pass "friend 입력연산자(>>) 확인됨"
}

check_class1_friend_output() {
    require_files "$H1"
    local stripped
    stripped=$(strip_comments "$H1")
    echo "$stripped" | grep -qP 'friend\b[^;{]*operator\s*<<' \
        || fail "friend 출력연산자(operator<<)를 찾을 수 없습니다"
    pass "friend 출력연산자(<<) 확인됨"
}

check_class1_friend_equality() {
    require_files "$H1"
    local stripped
    stripped=$(strip_comments "$H1")
    echo "$stripped" | grep -qP 'friend\b[^;{]*operator\s*==' \
        || fail "friend 비교연산자(operator==)를 찾을 수 없습니다"
    pass "friend 비교연산자(==) 확인됨"
}

check_class1_friend_plus() {
    require_files "$H1"
    local stripped
    stripped=$(strip_comments "$H1")
    echo "$stripped" | grep -qP 'friend\b[^;{]*operator\s*\+(?!\+)' \
        || fail "friend 덧셈연산자(operator+)를 찾을 수 없습니다"
    pass "friend 덧셈연산자(+) 확인됨"
}

check_class2_constructor() {
    require_files "$H2"
    local stripped cls2
    stripped=$(strip_comments "$H2")
    cls2=$(detect_class_name "$H2")
    [ -z "$cls2" ] && fail "클래스2를 찾을 수 없습니다"
    echo "$stripped" | grep -qP "(?<!~)\b${cls2}\s*\([^)]*\)\s*(:|\{)" \
        || fail "클래스2 생성자를 찾을 수 없습니다 (클래스: $cls2)"
    pass "클래스2 생성자 확인됨 (클래스: $cls2)"
}

check_class2_private_member() {
    require_files "$H1" "$H2"
    local stripped cls1 private_section member_count
    stripped=$(strip_comments "$H2")
    cls1=$(detect_class_name "$H1")
    echo "$stripped" | grep -qP "\b${cls1}\b\s+\w+\s*;" \
        || fail "클래스2에 클래스1형 멤버변수가 없습니다"
    private_section=$(echo "$stripped" | sed -n '/private/,/public/p')
    member_count=$(echo "$private_section" | grep -cP '^\s*[A-Za-z_][\w:<>]*\s+\w+\s*;')
    [ "$member_count" -lt 2 ] && fail "클래스2 private 멤버변수가 2개 미만입니다 (클래스1형 + 기타 1개 이상 필요, 현재: $member_count)"
    pass "클래스2 private 멤버변수 확인됨 (클래스1형 포함 ${member_count}개)"
}

check_class2_print() {
    require_files "$H2"
    local stripped
    stripped=$(strip_comments "$H2")
    echo "$stripped" | grep -qP '\bprint\s*\([^)]*\)' \
        || fail "클래스2 print 함수를 찾을 수 없습니다"
    pass "클래스2 print 함수 확인됨"
}

check_class2_get_set() {
    require_files "$H1" "$H2"
    local stripped cls1
    stripped=$(strip_comments "$H2")
    cls1=$(detect_class_name "$H1")
    echo "$stripped" | grep -qP "${cls1}\s*&\s*get\w*\s*\(" \
        || fail "클래스1형 객체를 참조형식으로 반환하는 접근함수를 찾을 수 없습니다"
    pass "클래스1형 객체 참조형 접근함수 확인됨"
}

# ------------------------------------------------------------------------
# 컴파일 체크 (2점)
# ------------------------------------------------------------------------

check_compile() {
    require_files "$H1" "$H2" "$MAIN"
    local bin err
    bin="/tmp/scoring2_bin_$$"
    err=$(g++ -std=c++17 -Wall -o "$bin" "$MAIN" 2>&1)
    local rc=$?
    rm -f "$bin"
    [ $rc -ne 0 ] && fail "컴파일 실패: $(echo "$err" | head -5)"
    pass "컴파일 성공"
}

# ------------------------------------------------------------------------
# 런타임 동작 체크 (아래 항목들은 필드 개수/타입을 가정하여 일반화된 숫자 입력을 사용합니다.
# 실제 제출물의 입력 형식이 다를 경우 NUM_FIELDS 조정 또는 gen_input 로직 보정이 필요할 수 있습니다.)
# ------------------------------------------------------------------------

check_input_output() {
    local bin out line_count
    bin=$(compile_or_fail) || fail "컴파일 실패로 런타임 테스트를 진행할 수 없습니다: ${bin#COMPILE_ERROR::}"
    out=$(gen_input 10 20 30 40 | timeout 5 "$bin" 2>&1)
    rm -f "$bin"
    line_count=$(echo "$out" | grep -cP '\S')
    [ "$line_count" -lt 2 ] && fail "입력 후 두 객체의 출력 결과가 충분하지 않습니다 (출력 라인: $line_count)"
    pass "입력연산자/출력연산자 동작 확인됨 (출력 라인: $line_count)"
}

check_increment() {
    local bin out lines
    bin=$(compile_or_fail) || fail "컴파일 실패로 런타임 테스트를 진행할 수 없습니다: ${bin#COMPILE_ERROR::}"
    out=$(gen_input 10 20 10 20 | timeout 5 "$bin" 2>&1)
    rm -f "$bin"
    lines=$(echo "$out" | grep -cP '\S')
    [ "$lines" -lt 5 ] && fail "전위/후위 증가연산자 적용 후 출력이 부족합니다 (총 출력 라인: $lines, 5줄 이상 예상: 입력2줄+증가결과3줄)"
    pass "전위/후위 증가연산자 출력 확인됨 (총 출력 라인: $lines) - 값 정확성은 표본 확인 권장"
}

check_equality() {
    # 참고: 두번째 객체는 비교 전에 증가연산자가 적용되므로(과제 명세상),
    # 초기값이 같더라도 비교 시점엔 값이 달라질 수 있습니다.
    # 따라서 same/different 중 "정확히 어느 쪽"이 나오는지가 아니라,
    # same/different 출력 로직 자체가 존재/동작하는지를 확인합니다.
    local bin out_a out_b hit_a hit_b
    bin=$(compile_or_fail) || fail "컴파일 실패로 런타임 테스트를 진행할 수 없습니다: ${bin#COMPILE_ERROR::}"
    out_a=$(gen_input 10 20 10 20 | timeout 5 "$bin" 2>&1)
    out_b=$(gen_input 10 20 90 90 | timeout 5 "$bin" 2>&1)
    rm -f "$bin"
    hit_a=$(echo "$out_a" | grep -qiP '\b(same|different)\b' && echo 1 || echo 0)
    hit_b=$(echo "$out_b" | grep -qiP '\b(same|different)\b' && echo 1 || echo 0)
    { [ "$hit_a" = "1" ] && [ "$hit_b" = "1" ]; } \
        || fail "비교 결과로 same/different 출력을 찾을 수 없습니다"
    # 서로 명백히 다른 값(90 vs 10)을 넣은 경우엔 반드시 different가 나와야 함
    echo "$out_b" | grep -qiP '\bdifferent\b' \
        || fail "값이 크게 다른 두 객체를 비교했는데 'different'가 출력되지 않았습니다"
    pass "비교연산자(==) 결과에 따른 same/different 출력 확인됨"
}

check_plus() {
    local bin out lines
    bin=$(compile_or_fail) || fail "컴파일 실패로 런타임 테스트를 진행할 수 없습니다: ${bin#COMPILE_ERROR::}"
    out=$(gen_input 10 20 30 40 | timeout 5 "$bin" 2>&1)
    rm -f "$bin"
    lines=$(echo "$out" | grep -cP '\S')
    [ "$lines" -lt 6 ] && fail "덧셈연산자(+) 결과 출력이 부족합니다 (총 출력 라인: $lines)"
    pass "덧셈연산자(+) 결과 출력 확인됨 (총 출력 라인: $lines) - 값 정확성은 표본 확인 권장"
}

# ------------------------------------------------------------------------
# 전체 실행 (모든 체크를 한 번에 돌려서 요약/총점 출력)
# ------------------------------------------------------------------------

# name:points 형태로 순서와 배점을 정의 (scoring2-test.json 과 동일한 배점)
ALL_CHECKS=(
    "namespace_check:1"
    "using_header_check:1"
    "class1_constructor_check:1"
    "class1_const_check:1"
    "class1_prefix_increment_operator_check:1"
    "class1_postfix_increment_operator_check:1"
    "class1_friend_input_operator_check:1"
    "class1_friend_output_operator_check:1"
    "class1_friend_equality_operator_check:1"
    "class1_friend_plus_operator_check:1"
    "class2_constructor_check:1"
    "class2_private_member_check:1"
    "class2_print_check:1"
    "class2_get_set_check:1"
    "compile_check:2"
    "input_output_check:1"
    "increment_check:1"
    "equlity_check:1"
    "plus_check:1"
)

run_all() {
    local script_path="$0"
    local total=0
    local max=0
    local name pts entry out rc msg mark

    printf '%-42s %4s  %s\n' "체크 항목" "배점" "결과"
    printf '%s\n' "--------------------------------------------------------------------"

    for entry in "${ALL_CHECKS[@]}"; do
        name="${entry%%:*}"
        pts="${entry##*:}"
        max=$((max + pts))

        # 각 체크는 exit로 종료되므로 하위 프로세스로 실행해 결과만 회수한다.
        out=$(bash "$script_path" "$name" 2>&1)
        rc=$?
        msg="${out#PASS: }"; msg="${msg#FAIL: }"

        if [ $rc -eq 0 ]; then
            total=$((total + pts))
            mark="[PASS]"
        else
            mark="[FAIL]"
        fi
        printf '%-42s %4s  %s %s\n' "$name" "$pts" "$mark" "$msg"
    done

    printf '%s\n' "--------------------------------------------------------------------"
    echo "총점: ${total} / ${max}"

    [ "$total" -eq "$max" ]
}

# ------------------------------------------------------------------------
# 디스패치
# ------------------------------------------------------------------------

CHECK="${1:-all}"

if [ "$CHECK" = "all" ]; then
    run_all
    exit $?
fi

resolve_files

case "$CHECK" in
    namespace_check)                          check_namespace ;;
    using_header_check)                       check_using_header ;;
    class1_constructor_check)                 check_class1_constructor ;;
    class1_const_check)                       check_class1_const ;;
    class1_prefix_increment_operator_check)   check_class1_prefix_increment ;;
    class1_postfix_increment_operator_check)  check_class1_postfix_increment ;;
    class1_friend_input_operator_check)       check_class1_friend_input ;;
    class1_friend_output_operator_check)      check_class1_friend_output ;;
    class1_friend_equality_operator_check)    check_class1_friend_equality ;;
    class1_friend_plus_operator_check)        check_class1_friend_plus ;;
    class2_constructor_check)                 check_class2_constructor ;;
    class2_private_member_check)              check_class2_private_member ;;
    class2_print_check)                       check_class2_print ;;
    class2_get_set_check)                     check_class2_get_set ;;
    compile_check)                            check_compile ;;
    input_output_check)                       check_input_output ;;
    increment_check)                          check_increment ;;
    equlity_check)                            check_equality ;;
    plus_check)                                check_plus ;;
    *) echo "FAIL: 알 수 없는 체크 이름: $CHECK"; exit 2 ;;
esac
