#!/usr/bin/env bash
# =============================================================================
# scoringm04.sh  -  m04 (book.h / bookGroup.h / main.cpp) 자동채점, 100점 만점
#
# 사용법
#   bash scoringm04.sh               # 전체 채점, 마지막 줄에 SCORE=NN 출력
#   bash scoringm04.sh 12            # 12번 항목만 채점 (만점이면 exit 0, 아니면 exit 1)
#   SCORE_DIR=경로 bash scoringm04.sh  # 다른 디렉터리를 채점
#
# 필요: bash 4+, perl, g++
# 방식: 주석을 제거하고 문자열 리터럴 내용을 비운 뒤 정규식으로 구조를 검사합니다.
#       (주석 안에 정답을 적어서 점수를 받는 경우를 막기 위함)
# =============================================================================

ONLY="${1:-}"
if [[ -n "${SCORE_DIR:-}" ]]; then cd "$SCORE_DIR" || exit 2; fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 이름+학번 namespace 판별 규칙: 영문으로 시작, 숫자 4자리 이상 포함 (예: hong20241234)
NS_RE='^[A-Za-z_][A-Za-z0-9_]*[0-9]{4,}[A-Za-z0-9_]*$'

# ----------------------------- 채점 도구 함수 --------------------------------
IDX=0; SCORE=0; TOTAL_MAX=0
declare -a E M ITEMLINE LINES

section() { LINES+=("" "$1"); }

award() { # 얻은점수 만점 설명
  IDX=$((IDX+1)); E[$IDX]=$1; M[$IDX]=$2
  SCORE=$((SCORE+$1)); TOTAL_MAX=$((TOTAL_MAX+$2))
  local mark="FAIL"; [[ $1 -eq $2 ]] && mark="PASS"
  ITEMLINE[$IDX]=$(printf '[%2d] [%s] (%2d/%2d) %s' "$IDX" "$mark" "$1" "$2" "$3")
  LINES+=("${ITEMLINE[$IDX]}")
}

chk() { # 만점 설명 명령...
  local m=$1 d=$2; shift 2
  if "$@" >/dev/null 2>&1; then award "$m" "$m" "$d"; else award 0 "$m" "$d"; fi
}

# 문자열($1)이 정규식($2)과 일치하는가 (여러 줄 대상, ^ 는 줄 시작)
rxs() { S="$1" RX="$2" perl -e 'exit((($ENV{S}//"") =~ /$ENV{RX}/m) ? 0 : 1)'; }

# 함수 전체(헤더+본문) 추출: $1=소스문자열, $2=헤더 정규식(괄호 포함). 첫 번째 정의만 출력
fn_text() {
  S="$1" FNH="$2" perl -e '
    $s = $ENV{S} // "";
    print $& if $s =~ /$ENV{FNH}\s*(?:const\s*)?(?:noexcept\s*)?(?<b>\{(?:[^{}]++|(?&b))*\})/;'
}

# bookGroup 생성자 추출 (초기화 리스트 포함)
ctor_text() {
  S="$1" perl -e '
    $s = $ENV{S} // "";
    print $& if $s =~ /\bbookGroup\s*\([^)]*\)\s*(?::\s*(?:\w+\s*(?:\([^()]*\)|\{[^{}]*\})\s*,?\s*)+)?(?<b>\{(?:[^{}]++|(?&b))*\})/;'
}

# 첫 번째 (std 제외) namespace 의 이름 / 중괄호 본문
ns_name() { S="$1" perl -e '$s=$ENV{S}//""; print $1 if $s=~/\bnamespace\s+(?!std\b)([A-Za-z_]\w*)\s*\{/'; }
ns_body() { S="$1" perl -e '$s=$ENV{S}//""; print $+{b} if $s=~/\bnamespace\s+(?!std\b)[A-Za-z_]\w*\s*(?<b>\{(?:[^{}]++|(?&b))*\})/'; }
ns_valid() { [[ $1 =~ $NS_RE ]]; }

# 주석 제거 / 문자열 리터럴 비우기
strip_comments() {
  perl -0777 -pe 's{("(?:\\.|[^"\\\n])*")|(\x27(?:\\.|[^\x27\\\n])*\x27)|//[^\n]*|/\*.*?\*/}{defined $1 ? $1 : defined $2 ? $2 : " "}gse'
}
blank_strings() {
  perl -0777 -pe 's{"(?:\\.|[^"\\\n])*"}{""}g; s{\x27(?:\\.|[^\x27\\\n])*\x27}{\x27\x27}g'
}

# 파일 찾기: 현재 폴더 우선, 없으면 하위 3단계까지
locate() {
  if [[ -f "./$1" ]]; then echo "./$1"; else
    find . -maxdepth 3 -type f -name "$1" -not -path './.git/*' -not -path './node_modules/*' 2>/dev/null | head -n1
  fi
}

load() { # 경로 -> 주석제거본(nc) 출력
  if [[ -n "$1" && -f "$1" ]]; then tr -d '\r' < "$1" | strip_comments; fi
}

# ------------------------------ 파일 읽기 -----------------------------------
BOOK_PATH=$(locate book.h)
GROUP_PATH=$(locate bookGroup.h)
MAIN_PATH=$(locate main.cpp)

BNC=$(load "$BOOK_PATH");  BS=$(printf '%s' "$BNC" | blank_strings)
GNC=$(load "$GROUP_PATH"); GS=$(printf '%s' "$GNC" | blank_strings)
MNC=$(load "$MAIN_PATH");  MS=$(printf '%s' "$MNC" | blank_strings)

GUARD_RX='(?:^\s*#\s*pragma\s+once\b|^\s*#\s*ifndef\s+(\w+)[ \t]*\n\s*#\s*define\s+\1\b[\s\S]*^\s*#\s*endif)'
NAMEN='(?:n|numOfBook)'
MAXN='(?:max|maxBook|100)'

# =============================================================================
# 1. book.h (37점)
# =============================================================================
section "[book.h] 37점"
BOOK_NS=$(ns_name "$BS"); BOOK_NS_BODY=$(ns_body "$BS")

chk 3 "book.h 파일 존재"                                   test -n "$BOOK_PATH"
chk 3 "헤더가드 (#pragma once 또는 #ifndef/#define/#endif)" rxs "$BNC" "$GUARD_RX"
chk 2 "#include <iostream>"                                 rxs "$BNC" '^\s*#\s*include\s*<iostream>'
chk 2 "#include <string>"                                   rxs "$BNC" '^\s*#\s*include\s*<string>'
chk 2 "namespace 이름이 이름+학번 형태"                      ns_valid "$BOOK_NS"
chk 3 "namespace 안에 class book 정의"                       rxs "$BOOK_NS_BODY" '\bclass\s+book\b'

IFBRACE='\bif\s*(?<p>\((?:[^()]++|(?&p))*\))\s*\{[^{}]*\b(?:exit|abort)\s*\([^)]*\)\s*;[^{}]*\}'
TID=$(fn_text "$BS" '\btestID\s*\(\s*\)')
TPR=$(fn_text "$BS" '\btestPrice\s*\(\s*\)')
chk 3 "testID: if 뒤에 {} 로 묶고 그 안에서 exit"           rxs "$TID" "$IFBRACE"
chk 3 "testPrice: if 뒤에 {} 로 묶고 그 안에서 exit"        rxs "$TPR" "$IFBRACE"

PRE=$(fn_text "$BS" '\boperator\s*\+\+\s*\(\s*\)')
PRE_REF=$(fn_text "$BS" '\bbook\s*&\s*operator\s*\+\+\s*\(\s*\)')
chk 3 "전위 ++ 의 리턴형이 book&"                           test -n "$PRE_REF"
chk 3 "전위 ++ 에서 this 사용"                              rxs "$PRE" '\bthis\b'

POST=$(fn_text "$BS" '\boperator\s*\+\+\s*\(\s*int\s*\w*\s*\)')
POST_VAL=$(fn_text "$BS" '\bbook\s+operator\s*\+\+\s*\(\s*int\s*\w*\s*\)')
chk 2 "후위 ++ 에서 this 사용"                              rxs "$POST" '\bthis\b'
chk 2 "후위 ++ 는 값(book)으로 리턴 (참조 아님)"             test -n "$POST_VAL"

PLUS=$(fn_text "$BS" '\boperator\s*\+=\s*\(\s*(?:const\s+)?int\b[^)]*\)')
PLUS_REF=$(fn_text "$BS" '\bbook\s*&\s*operator\s*\+=\s*\(\s*(?:const\s+)?int\b[^)]*\)')
chk 2 "+= 정의 (매개변수 int)"                              test -n "$PLUS"
chk 2 "+= 의 리턴형이 book&"                                test -n "$PLUS_REF"
chk 2 "+= 에서 this 사용"                                   rxs "$PLUS" '\bthis\b'

# =============================================================================
# 2. bookGroup.h (37점)
# =============================================================================
section "[bookGroup.h] 37점"
GRP_NS=$(ns_name "$GS"); GRP_NS_BODY=$(ns_body "$GS")

chk 2 "bookGroup.h 파일 존재"                                test -n "$GROUP_PATH"
chk 2 "헤더가드 (#pragma once 또는 #ifndef/#define/#endif)"  rxs "$GNC" "$GUARD_RX"
chk 3 "상수 max(maxBook) = 100 선언"                         rxs "$GS" '\b(?:const|constexpr)\b[^;{}()]*\b(?:max|maxBook)\s*(?:=\s*100|\{\s*100\s*\})\s*;'
chk 2 "namespace 이름이 이름+학번 형태"                       ns_valid "$GRP_NS"
chk 2 "namespace 안에 class bookGroup 정의"                   rxs "$GRP_NS_BODY" '\bclass\s+bookGroup\b'
chk 2 "멤버: std::string groupName"                           rxs "$GS" '\bstd::string\s+groupName\b'
chk 2 "멤버: std::array<book, max> bookList"                  rxs "$GS" "\\bstd::array\\s*<\\s*(?:\\w+::)*book\\s*,\\s*$MAXN\\s*>\\s*bookList\\b"
chk 2 "멤버: int n(numOfBook)"                                rxs "$GS" "\\bint\\s+$NAMEN\\b"

CTOR=$(ctor_text "$GS")
chk 1 "생성자: 매개변수 1개 (string)"                         rxs "$GS" '\bbookGroup\s*\(\s*(?:const\s+)?(?:std::)?string\b[^,()]*\)\s*[:{]'
chk 2 "생성자: groupName 초기화"                              rxs "$CTOR" '\bgroupName\s*(?:[\({]\s*\w+\s*[\)}]|=\s*\w+)'
if rxs "$CTOR" "\\b$NAMEN\\s*(?:[\\({]\\s*0\\s*[\\)}]|=\\s*0\\b)" \
   || rxs "$GS" "\\bint\\s+$NAMEN\\s*(?:=\\s*0|\\{\\s*0?\\s*\\})\\s*;"; then
  award 2 2 "생성자: n(numOfBook)을 0으로 초기화"
else
  award 0 2 "생성자: n(numOfBook)을 0으로 초기화"
fi

ADD=$(fn_text "$GS" '\baddBook\s*\([^)]*\)')
chk 1 "addBook: 매개변수 const book&"                         rxs "$ADD" '\baddBook\s*\(\s*const\s+(?:\w+::)*book\s*&\s*\w*\s*\)'
#chk 2 "addBook: n >= max 이면 프로그램 종료"                  rxs "$ADD" "\\bif\\s*\\(\\s*(?:$NAMEN\\s*>=\\s*$MAXN|$MAXN\\s*<=\\s*$NAMEN|$NAMEN\\s*>\\s*(?:max|maxBook)\\s*-\\s*1)\\s*\\)\\s*\\{?[^{}]*?\\b(?:exit|abort|quick_exit|terminate)\\s*\\("
chk 2 "addBook: n >= max 이면 프로그램 종료"                  rxs "$ADD" "\\bif\\s*\\(\\s*(?:$NAMEN\\s*>=\\s*$MAXN|$MAXN\\s*<=\\s*$NAMEN|$NAMEN\\s*>\\s*(?:max|maxBook)\\s*-\\s*1)\\s*\\)\\s*\\{?[^{}]*?\\b(?:exit|abort|quick_exit|terminate)\\s*\\("chk 2 "addBook: bookList[n] 에 매개변수 할당"                 rxs "$ADD" "\\baddBook\\s*\\(\\s*const\\s+(?:\\w+::)*book\\s*&\\s*(\\w+)\\s*\\)[\\s\\S]*?\\bbookList\\s*(?:\\[\\s*$NAMEN\\s*\\]|\\.at\\s*\\(\\s*$NAMEN\\s*\\))\\s*=\\s*\\1\\b"
chk 1 "addBook: n 을 1 증가"                                  rxs "$ADD" "(?:\\+\\+\\s*$NAMEN\\b|\\b$NAMEN\\s*\\+\\+|\\b$NAMEN\\s*\\+=\\s*1\\b|\\b$NAMEN\\s*=\\s*$NAMEN\\s*\\+\\s*1\\b)"

PR=$(fn_text "$GS" '\bprint\s*\(\s*\)')
chk 2 "print: const 멤버함수"                                 rxs "$GS" '\bprint\s*\(\s*\)\s*const\b'
print_name_ok() { rxs "$PR" '\bcout\b' && rxs "$PR" '\b(?:groupName|getGroupName)\b'; }
chk 1 "print: 표준스트림(cout)으로 groupName 출력"            print_name_ok
if rxs "$PR" "\\b(?:for|while)\\s*\\([^{}]*?(?:<|!=)\\s*$NAMEN\\b" && rxs "$PR" '\bbookList\b'; then
  award 2 2 "print: bookList 를 n 개만 출력 (for/while 이 n 까지)"
else
  award 0 2 "print: bookList 를 n 개만 출력 (for/while 이 n 까지)"
fi

chk 1 "getGroupName: 참조 리턴"                               rxs "$GS" '\bstring\s*&\s*getGroupName\s*\(\s*\)'
chk 1 "getGroupName: const 멤버함수"                          rxs "$GS" '\bgetGroupName\s*\(\s*\)\s*const\b'
SET=$(fn_text "$GS" '\bsetGroupName\s*\([^)]*\)')
chk 1 "setGroupName: 참조 매개변수"                           rxs "$GS" '\bsetGroupName\s*\(\s*(?:const\s+)?(?:std::)?string\s*&'
chk 1 "setGroupName: groupName 에 대입"                       rxs "$SET" '\bgroupName\s*(?:=\s*\w+|\.assign\b)'

# =============================================================================
# 3. main.cpp (17점)
# =============================================================================
section "[main.cpp] 17점"

# book 타입 선언문에서 쉼표(최상위)로 나뉜 선언자를 모두 인식하고, 초기화된 객체 이름만 출력
BOOK_OBJS=$(S="$MS" perl -e '
  $s = $ENV{S} // "";
  while ($s =~ /\b(?:\w+::)*book\s+([A-Za-z_][^;]*);/g) {
    my ($d, $depth, $cur, @parts) = ($1, 0, "");
    for my $c (split //, $d) {
      if    ($c =~ /[\(\{\[]/) { $depth++ }
      elsif ($c =~ /[\)\}\]]/) { $depth-- }
      if ($c eq "," && $depth == 0) { push @parts, $cur; $cur = "" } else { $cur .= $c }
    }
    push @parts, $cur;
    for (@parts) { print "$1\n" if /^\s*([A-Za-z_]\w*)\s*(?:\{|\(|=)/ }
  }')
N_OBJ=$(printf '%s' "$BOOK_OBJS" | grep -c .)
PTR=$(S="$MS" perl -e '$s=$ENV{S}//"";
  if($s=~/\b(?:\w+::)*bookGroup\s*\*\s*(\w+)/){print $1}
  elsif($s=~/\bauto\s*\*?\s*(\w+)\s*=\s*new\s+(?:\w+::)*bookGroup/){print $1}')

calls_of() { # 메서드명 -> 포인터를 통한 호출의 인자(한 줄에 하나)
  PTR="$PTR" S="$MS" METH="$1" perl -e '
    $s=$ENV{S}//""; $p=quotemeta($ENV{PTR}//""); $m=quotemeta($ENV{METH});
    exit 0 if $p eq "";
    while ($s =~ /(?:\b$p\s*->|\(\s*\*\s*$p\s*\)\s*\.)\s*$m\s*\(\s*([^()]*?)\s*\)/g) { print "$1\n" }'
}
mapfile -t ADD_ARGS < <(calls_of addBook)

args_ok() { # 인식된 book 객체가 1개 이상이고, 전부 addBook 인자로 쓰였는가
  local o; [[ -n "$BOOK_OBJS" ]] || return 1
  while IFS= read -r o; do
    printf '%s\n' "${ADD_ARGS[@]}" | grep -qxF -- "$o" || return 1
  done <<<"$BOOK_OBJS"
  return 0
}
print_called() { calls_of print | grep -qx ''; }
delete_ok() { [[ -n "$PTR" ]] && rxs "$MS" "\\bdelete\\s*\\(?\\s*$PTR\\s*\\)?\\s*;"; }

chk 2 "#include \"bookGroup.h\""                              rxs "$MNC" '^\s*#\s*include\s*"bookGroup\.h"'
chk 2 "main 함수 존재"                                       rxs "$MS" '\bint\s+main\s*\('
obj_ge() { (( N_OBJ >= $1 )); }
chk 1 "book 객체 1번째 선언 및 초기화 (발견: ${N_OBJ}개)" obj_ge 1
chk 1 "book 객체 2번째 선언 및 초기화"                   obj_ge 2
chk 1 "book 객체 3번째 선언 및 초기화"                   obj_ge 3
chk 1 "bookGroup 포인터 변수 선언"                           test -n "$PTR"
chk 1 "new bookGroup 으로 동적 할당"                         rxs "$MS" '\bnew\s+(?:\w+::)*bookGroup\s*[\(\{]'
chk 1 "new bookGroup(...) 에 초기값 전달"                    rxs "$MS" '\bnew\s+(?:\w+::)*bookGroup\s*[\(\{]\s*[^)}\s]'
chk 2 "포인터로 addBook 3회 이상 호출"                       test "${#ADD_ARGS[@]}" -ge 3
chk 1 "선언한 book 객체를 모두 addBook 에 전달 (${N_OBJ}개 중)" args_ok
chk 2 "포인터로 print 호출"                                  print_called
chk 2 "동적 할당 메모리 해제 (delete)"                       delete_ok

# =============================================================================
# 4. 컴파일 / 출력 (9점)
# =============================================================================
section "[컴파일/출력] 9점"
EXE="$WORK/a.out"; COMPILED=0
if [[ -n "$MAIN_PATH" ]]; then
  INC=()
  for f in "$BOOK_PATH" "$GROUP_PATH" "$MAIN_PATH"; do
    [[ -n "$f" ]] && INC+=("-I$(dirname "$f")")
  done
  timeout 60 g++ -std=c++17 -Wall "${INC[@]}" "$MAIN_PATH" -o "$EXE" >"$WORK/compile.log" 2>&1 && COMPILED=1
fi
chk 5 "컴파일 성공 (g++ -std=c++17)" test "$COMPILED" -eq 1
if (( ! COMPILED )) && [[ -s "$WORK/compile.log" ]]; then
  LINES+=("      └ 컴파일 오류(앞부분):" "$(head -n 12 "$WORK/compile.log" | sed 's/^/        /')")
fi

OUT=""; RC=1
if (( COMPILED )); then
  OUT=$(timeout 5 "$EXE" </dev/null 2>&1); RC=$?
fi

# main.cpp 에서 학생이 쓴 문자열(제목, 그룹명) 추출
LITS=$(S="$MNC" perl -e '
  $s = $ENV{S} // "";
  while ($s =~ /\b(?:\w+::)*book\s+([A-Za-z_](?:"(?:\\.|[^"\\])*"|[^;"])*);/g) {
    my ($d, $depth, $cur, $q, @parts) = ($1, 0, "", 0);
    for my $c (split //, $d) {
      if ($c eq "\"") { $q = !$q }
      elsif (!$q) {
        if    ($c =~ /[\(\{\[]/) { $depth++ }
        elsif ($c =~ /[\)\}\]]/) { $depth-- }
        if ($c eq "," && $depth == 0) { push @parts, $cur; $cur = ""; next }
      }
      $cur .= $c;
    }
    push @parts, $cur;
    for (@parts) { print "T:$1\n" if /^\s*[A-Za-z_]\w*\s*[\(\{=].*?"((?:\\.|[^"\\])*)"/ }
  }
  print "G:$1\n" if $s =~ /\bnew\s+(?:\w+::)*bookGroup\s*[\(\{]\s*"((?:\\.|[^"\\])*)"/;')
GLIT=$(grep '^G:' <<<"$LITS" | head -n1 | sed 's/^G://')
mapfile -t TLIT < <(grep '^T:' <<<"$LITS" | sed 's/^T://')

ran_ok()    { (( COMPILED )) && [[ $RC -eq 0 && -n "$OUT" ]]; }
group_ok()  { (( COMPILED )) || return 1
              if [[ -z "$GLIT" ]]; then [[ -n "$OUT" ]]; else grep -qF -- "$GLIT" <<<"$OUT"; fi; }
titles_ok() { (( COMPILED )) || return 1; (( ${#TLIT[@]} >= 3 )) || return 1
              local t; for t in "${TLIT[@]}"; do grep -qF -- "$t" <<<"$OUT" || return 1; done; }
format_ok() { (( COMPILED )) || return 1; [[ -n "$OUT" ]] || return 1
              ! grep -qi 'invalid' <<<"$OUT" && (( $(wc -l <<<"$OUT") >= 4 )); }

chk 1 "정상 실행 (종료코드 0, 출력 있음)"                    ran_ok
chk 1 "그룹명 출력"                                          group_ok
chk 1 "book 3권의 제목이 모두 출력"                          titles_ok
chk 1 "오류 메시지 없이 4줄 이상 출력 (그룹 + 책 3권)"         format_ok

# ------------------------------- 결과 출력 -----------------------------------
if [[ -n "$ONLY" ]]; then
  if [[ ! "$ONLY" =~ ^[0-9]+$ ]] || (( ONLY < 1 || ONLY > IDX )); then
    echo "항목 번호는 1~$IDX 사이여야 합니다."; exit 2
  fi
  echo "${ITEMLINE[$ONLY]}"
  [[ ${E[$ONLY]} -eq ${M[$ONLY]} ]]; exit $?
fi

echo "========== m04 자동채점 결과 =========="
printf '%s\n' "${LINES[@]}"
echo ""
echo "======================================="
echo "총점: $SCORE / $TOTAL_MAX"
echo "SCORE=$SCORE"
exit 0
