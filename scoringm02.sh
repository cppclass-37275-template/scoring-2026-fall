#!/usr/bin/env bash
# =====================================================================
# scoringm02.sh  -  실습 m02 (dayOfYear / holiday / holidayGroup) 자동채점
# 총점 100점 / 항목 61개
#   [1] dayOfYear.h    35점 (01~17)
#   [2] holiday.h      10점 (18~23)
#   [3] holidayGroup.h 30점 (24~45)
#   [4] main.cpp       15점 (46~57)
#   [5] 컴파일/출력    10점 (58~61)
#
# 사용법
#   ./scoringm02.sh              전체 채점 (현재 디렉터리)
#   ./scoringm02.sh <경로>        전체 채점 (해당 디렉터리)
#   ./scoringm02.sh <번호> [경로] 해당 번호 항목만 판정: 통과 exit 0 / 실패 exit 1
#                                (GitHub Classroom 항목별 Run Command 용)
# 필요 도구: bash, perl, g++, timeout
# =====================================================================

MODE=""
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then MODE="$1"; shift; fi
DIR="${1:-.}"
cd "$DIR" || { echo "디렉터리를 열 수 없습니다: $DIR"; exit 2; }

BUILD_FIRST=58        # 컴파일/실행이 필요한 첫 항목 번호
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SCORE=0; IDX=0; FOUND=0; TARGET=1

# ---------------------------------------------------------------------
# 헬퍼
# ---------------------------------------------------------------------
say() { [ -z "$MODE" ] && echo "$@"; }

# has FILE REGEX : perl 정규식이 파일 전체(개행 포함)에서 매치되면 성공
has() {
  perl -0777 -e '($re,$f)=@ARGV; open(F,"<",$f) or exit 1; $t=<F>; exit((defined $t && $t =~ /$re/) ? 0 : 1)' "$2" "$1" 2>/dev/null
}

# strip SRC DST : 주석(// , /* */)을 제거한 사본 (SRC가 비면 빈 파일)
strip() {
  if [ -n "$1" ]; then
    perl -0777 -pe 's{/\*.*?\*/}{ }gs; s{//[^\n]*}{}g' "$1" > "$2" 2>/dev/null || : > "$2"
  else
    : > "$2"
  fi
}

# body FILE REGEX : REGEX 매치 지점부터 그 뒤 첫 { ... } 블록 끝까지 출력
body() {
  perl -0777 -e '
    ($f,$re)=@ARGV; open(F,"<",$f) or exit 1; $t=<F>;
    exit 1 unless defined $t && $t =~ /$re/;
    $s=$-[0]; $e=$+[0]; $i=index($t,"{",$e); exit 1 if $i<0;
    $d=0;
    for($j=$i;$j<length($t);$j++){
      $c=substr($t,$j,1);
      if($c eq "{"){$d++} elsif($c eq "}"){$d--; last if $d==0}
    }
    print substr($t,$s,$j-$s+1);
  ' "$1" "$2" 2>/dev/null
}

find_f() { find . -path ./.git -prune -o -type f -name "$1" -print 2>/dev/null | head -n1; }

# item 배점 "설명" 명령...   (항목 번호는 호출 순서대로 1부터)
item() {
  local pts=$1 desc=$2; shift 2
  IDX=$((IDX+1))
  local ok=0
  "$@" >/dev/null 2>&1 && ok=1
  [ "$ok" -eq 1 ] && SCORE=$((SCORE+pts))
  if [ -z "$MODE" ]; then
    printf '  %02d. [%2d/%-2d] %s\n' "$IDX" $((ok*pts)) "$pts" "$desc"
  elif [ "$IDX" -eq "$MODE" ]; then
    FOUND=1; TARGET=$((1-ok))
    printf '[%02d] %s : %s\n' "$IDX" "$desc" "$([ $ok -eq 1 ] && echo 통과 || echo 실패)"
  fi
}

guard() {
  has "$1" '(?m)^\s*#\s*pragma\s+once\b' ||
  has "$1" '(?ms)^\s*#\s*ifndef\s+(\w+)\s*\n\s*#\s*define\s+\1\b.*^\s*#\s*endif'
}
nsname() { perl -0777 -ne 'print $1 if /\bnamespace\s+(?!std\b)(\w+)\s*\{/' "$1" 2>/dev/null; }
ns_has_class() {
  body "$1" '\bnamespace\s+(?!std\b)\w+\s*(?=\{)' > "$WORK/ns.txt"
  has "$WORK/ns.txt" "\\bclass\\s+$2\\b"
}
ns_note() { [ -n "$1" ] && [[ ! "$1" =~ [0-9] ]] && say "      (참고) namespace 이름 '$1' 에 숫자(학번)가 없습니다 - 감점 없음, 확인 필요"; }

# ---------------------------------------------------------------------
say "===== [1] dayOfYear.h (35점) ====="
# ---------------------------------------------------------------------
DAY="$(find_f dayOfYear.h)"
F="$WORK/day.h"; strip "$DAY" "$F"
item 2 "dayOfYear.h 파일 존재" test -n "$DAY"
item 2 "dayOfYear.h 헤더가드 (#pragma once 또는 #ifndef/#define/#endif)" guard "$F"
item 2 "dayOfYear.h #include <iostream>" has "$F" '#\s*include\s*<iostream>'
NS="$(nsname "$F")"
item 1 "dayOfYear.h namespace 정의" test -n "$NS"
item 2 "namespace 안에 class dayOfYear 정의" ns_has_class "$F" dayOfYear
ns_note "$NS"

body "$F" 'void\s+updateDay\s*\(\s*(?:void)?\s*\)' > "$WORK/upd.txt"
body "$WORK/upd.txt" '\bwhile\s*\([^)]*\)' > "$WORK/whl.txt"
item 4 "updateDay: while 사용 (한 달보다 큰 day 처리)" has "$WORK/upd.txt" '\bwhile\s*\('
item 3 "updateDay: while 끝에서 month 변경 후 maxDay = daysInMonth[month] 갱신" \
  has "$WORK/whl.txt" '(?s)(?:\+\+\s*month|\bmonth\s*(?:\+\+|\+=|=(?!=)))[^;]*;.*\bmaxDay\s*=\s*daysInMonth\s*\[\s*month\s*\]'

body "$F" 'operator\s*\+\+\s*\(\s*(?:void)?\s*\)' > "$WORK/pre.txt"
item 2 "전위 ++ 의 리턴형이 dayOfYear&" has "$F" 'dayOfYear\s*&\s*operator\s*\+\+\s*\(\s*(?:void)?\s*\)'
item 2 "전위 ++ 에서 this 사용" has "$WORK/pre.txt" '\bthis\b'

body "$F" 'operator\s*\+\+\s*\(\s*int\s*\w*\s*\)' > "$WORK/post.txt"
item 1 "후위 ++ 정의 (값 dayOfYear 로 리턴, 참조 아님)" has "$F" 'dayOfYear\s+operator\s*\+\+\s*\(\s*int\s*\w*\s*\)'
item 2 "후위 ++ 에서 this 사용" has "$WORK/post.txt" '\bthis\b'

body "$F" 'operator\s*\+=\s*\(' > "$WORK/pe.txt"
item 2 "+= 정의 (매개변수 int)" has "$F" 'operator\s*\+=\s*\(\s*(?:const\s+)?int\b'
item 2 "+= 의 리턴형이 dayOfYear&" has "$F" 'dayOfYear\s*&\s*operator\s*\+=\s*\('
item 2 "+= 에서 this 사용" has "$WORK/pe.txt" '\bthis\b'

plus_member() {
  has "$F" 'operator\s*\+\s*\(\s*(?:const\s+)?int\b' &&
  ! has "$F" 'friend[^;{}()]*operator\s*\+\s*\('
}
body "$F" 'operator\s*\+\s*\(\s*(?:const\s+)?int\b[^)]*\)' > "$WORK/plus.txt"
item 2 "이항 + 가 friend 가 아닌 멤버함수 (매개변수 int)" plus_member
item 2 "이항 + 에서 += 사용 (day 직접 += 는 불인정)" \
  has "$WORK/plus.txt" '(?:\*\s*this|\b(?!day\b)\w+|\))\s*\+='
item 2 "이항 + 에서 this 사용" has "$WORK/plus.txt" '\bthis\b'

# ---------------------------------------------------------------------
say "===== [2] holiday.h (10점) ====="
# ---------------------------------------------------------------------
HOL="$(find_f holiday.h)"
F="$WORK/hol.h"; strip "$HOL" "$F"
item 2 "holiday.h 파일 존재" test -n "$HOL"
item 2 "holiday.h 헤더가드 (#pragma once 또는 #ifndef/#define/#endif)" guard "$F"
item 2 "holiday.h #include \"dayOfYear.h\"" has "$F" '#\s*include\s*"dayOfYear\.h"'
item 1 "holiday.h #include <string>" has "$F" '#\s*include\s*<string>'
NS="$(nsname "$F")"
item 1 "holiday.h namespace 정의" test -n "$NS"
item 2 "namespace 안에 class holiday 정의" ns_has_class "$F" holiday
ns_note "$NS"

# ---------------------------------------------------------------------
say "===== [3] holidayGroup.h (30점) ====="
# ---------------------------------------------------------------------
HG="$(find_f holidayGroup.h)"
F="$WORK/hg.h"; strip "$HG" "$F"
item 2 "holidayGroup.h 파일 존재" test -n "$HG"
item 2 "holidayGroup.h 헤더가드 (#pragma once 또는 #ifndef/#define/#endif)" guard "$F"
NS="$(nsname "$F")"
item 1 "holidayGroup.h namespace 정의" test -n "$NS"
item 2 "namespace 안에 class holidayGroup 정의" ns_has_class "$F" holidayGroup
ns_note "$NS"
item 3 "상수 max = 10 선언" has "$F" '(?:const|constexpr)\b[^;()]*\bmax\s*(?:=\s*10\b|\{\s*10\s*\})'
item 1 "멤버: std::string groupName" has "$F" 'std::string\s+groupName\b'
item 2 "멤버: std::array<holiday, max> holidayList" has "$F" 'std::array\s*<\s*(?:\w+::)?holiday\s*,\s*max\s*>\s*holidayList\b'
item 1 "멤버: int n" has "$F" '\bint\s+n\b'

PARAMS="$(perl -0777 -ne 'print $1 if /\bholidayGroup\s*\(([^)]*)\)/' "$F" 2>/dev/null)"
perl -0777 -ne 'print $1 if /(\bholidayGroup\s*\([^)]*\).*?)(?=\bvoid\b|\bint\b|\bstd::|\bconst\b|\bprivate\b|\bpublic\b|\bholiday\b|\}\s*;|\z)/s' "$F" > "$WORK/ct.txt" 2>/dev/null
ctor_one_param() { [ -n "${PARAMS//[[:space:]]/}" ] && [[ "$PARAMS" != *,* ]]; }
n_zero() {
  has "$WORK/ct.txt" '\bn\s*(?:\{\s*0\s*\}|\(\s*0\s*\)|=\s*0\b)' ||
  has "$F" '\bint\s+n\s*(?:\{\s*0\s*\}|=\s*0)'
}
item 2 "생성자: 매개변수 1개" ctor_one_param
item 1 "생성자: groupName 초기화" has "$WORK/ct.txt" '\bgroupName\s*(?:\{|\(|=)'
item 1 "생성자: n 을 0으로 초기화" n_zero

body "$F" '(?i)\baddholiday\s*\([^)]*\)' > "$WORK/add.txt"
item 1 "addHoliday: 매개변수 const holiday&" has "$F" '(?i)\baddholiday\s*\(\s*const\s+(?:\w+::)?holiday\s*&'
item 1 "addHoliday: n >= max 이면 검사" has "$WORK/add.txt" '\bn\s*(?:>=|==)\s*max\b|\bmax\s*(?:<=|==)\s*n\b|\bn\s*>\s*max\s*-\s*1\b|\bn\s*>=\s*(?:holidayList\s*\.\s*size\s*\(\s*\)|10)'
item 1 "addHoliday: 프로그램 종료 (exit)" has "$WORK/add.txt" '\b(?:std::)?exit\s*\(|\babort\s*\('
item 1 "addHoliday: holidayList[n] 에 매개변수 할당" has "$WORK/add.txt" '\bholidayList\s*(?:\[\s*n\s*(?:\+\+\s*)?\]|\.\s*at\s*\(\s*n\s*\))\s*='
item 1 "addHoliday: n 을 1 증가" has "$WORK/add.txt" '\bn\s*\+\+|\+\+\s*n\b|\bn\s*\+=\s*1\b|\bn\s*=\s*n\s*\+\s*1\b'

body "$F" 'void\s+print\s*\(\s*(?:void)?\s*\)\s*(?:const\s*)?(?=\{)' > "$WORK/prt.txt"
prt_loop() { has "$WORK/prt.txt" '\b(?:for|while)\s*\([^)]*\bn\b' && has "$WORK/prt.txt" '\bholidayList\b'; }
item 2 "print: const 멤버함수" has "$F" 'void\s+print\s*\(\s*(?:void)?\s*\)\s*const\b'
item 1 "print: groupName 출력" has "$WORK/prt.txt" '\bgroupName\b'
item 1 "print: holidayList 를 n 개만 출력 (for/while 이 n 까지)" prt_loop

item 1 "getGroupName: 참조 리턴" has "$F" '(?:const\s+)?std::string\s*&\s*getGroupName\s*\('
item 1 "getGroupName: const 멤버함수" has "$F" 'getGroupName\s*\(\s*(?:void)?\s*\)\s*const\b'
item 1 "setGroupName: 참조 매개변수" has "$F" 'setGroupName\s*\(\s*(?:const\s+)?std::string\s*&'

# ---------------------------------------------------------------------
say "===== [4] main.cpp (15점) ====="
# ---------------------------------------------------------------------
MAIN="$(find_f main.cpp)"
M="$WORK/main.cpp"; strip "$MAIN" "$M"

# holiday 객체 이름: 여러 줄 / 한 줄 선언 (holiday a{..}, b{..}, c{..};) 모두 인식
OBJS="$(perl -0777 -ne '
  my $t = $_;
  while ($t =~ /\bholiday\s+(?=\w+\s*[\{\(=])/g) {
    my ($i,$d,$seg,@segs) = (pos($t),0,"");
    for (; $i < length($t); $i++) {
      my $c = substr($t,$i,1);
      if    ($c =~ /[\{\(\[]/) { $d++ }
      elsif ($c =~ /[\}\)\]]/) { $d-- }
      last if $d < 0 || ($d == 0 && $c eq ";");
      if ($d == 0 && $c eq ",") { push @segs, $seg; $seg = ""; next }
      $seg .= $c;
    }
    push @segs, $seg;
    for my $g (@segs) { print "$1\n" if $g =~ /^\s*(\w+)\s*[\{\(=]/ }
  }' "$M" 2>/dev/null | sort -u)"
NOBJ="$(printf '%s' "$OBJS" | grep -c .)"

PTR="$(perl -0777 -ne 'print $1 if /(?:\b(?:\w+::)?holidayGroup\s*\*\s*|\bauto\s*\*?\s*)(\w+)\s*[=\{\(]\s*new\s+(?:\w+::)?holidayGroup\b/' "$M" 2>/dev/null)"
PDECL="$(perl -0777 -ne 'print $1 if /\bholidayGroup\s*\*\s*(\w+)/' "$M" 2>/dev/null)"
P="${PTR:-$PDECL}"

CALLS=0; VALID=0
if [ -n "$P" ]; then
  read -r CALLS VALID < <(PTRN="$P" OBJS="$OBJS" perl -0777 -ne '
    my %o = map { $_ => 1 } split /\s+/, $ENV{OBJS};
    my $p = quotemeta $ENV{PTRN};
    my ($c,$v) = (0,0);
    while (/(?:\b$p\s*->|\(\s*\*\s*$p\s*\)\s*\.)\s*addholiday\s*\(\s*((?:\w+::)?\w+)/gi) {
      my $a = $1; $a =~ s/^.*:://; $c++; $v++ if $o{$a} || $a eq "holiday";
    }
    print "$c $v\n";' "$M" 2>/dev/null)
fi
CALLS="${CALLS:-0}"; VALID="${VALID:-0}"

objs_ge()      { [ "$NOBJ" -ge "$1" ]; }
ptr_decl()     { [ -n "$P" ]; }
ptr_new()      { has "$M" 'new\s+(?:\w+::)?holidayGroup\b'; }
ptr_new_init() { has "$M" 'new\s+(?:\w+::)?holidayGroup\s*[\{\(]\s*[^\s\)\}]'; }
calls_ok()     { [ "$CALLS" -ge 3 ]; }
args_ok()      { [ "$CALLS" -ge 3 ] && [ "$VALID" -eq "$CALLS" ]; }
ptr_print()    { [ -n "$P" ] && has "$M" "(?:\\b$P\\s*->|\\(\\s*\\*\\s*$P\\s*\\)\\s*\\.)\\s*print\\s*\\("; }
ptr_delete()   { [ -n "$P" ] && has "$M" "\\bdelete\\s+$P\\b"; }

item 2 "main.cpp #include \"holidayGroup.h\"" has "$M" '#\s*include\s*"holidayGroup\.h"'
item 2 "main 함수 존재" has "$M" '\bmain\s*\('
item 1 "holiday 객체 1번째 선언 및 초기화" objs_ge 1
item 1 "holiday 객체 2번째 선언 및 초기화" objs_ge 2
item 1 "holiday 객체 3번째 선언 및 초기화" objs_ge 3
item 1 "holidayGroup 포인터 변수 선언" ptr_decl
item 1 "new holidayGroup 으로 동적 할당" ptr_new
item 1 "new holidayGroup(...) 에 초기값 전달" ptr_new_init
item 2 "포인터로 addHoliday 3회 이상 호출" calls_ok
item 1 "선언한 holiday 객체를 모두 addHoliday 에 전달" args_ok
item 1 "포인터로 print 호출" ptr_print
item 1 "동적 할당 메모리 해제 (delete)" ptr_delete

# ---------------------------------------------------------------------
say "===== [5] 컴파일 / 출력 (10점) ====="
# ---------------------------------------------------------------------
BUILD_OK=0; RUN_RC=1; LOG=""
: > "$WORK/out.txt"
if [ -n "$MAIN" ] && { [ -z "$MODE" ] || [ "$MODE" -ge "$BUILD_FIRST" ]; }; then
  INCS=()
  for h in "$DAY" "$HOL" "$HG" "$MAIN"; do
    [ -n "$h" ] && INCS+=("-I$(dirname "$h")")
  done
  LOG="$(timeout 120 g++ -std=c++17 "${INCS[@]}" "$MAIN" -o "$WORK/a.out" 2>&1)"
  [ $? -eq 0 ] && BUILD_OK=1
  if [ "$BUILD_OK" -eq 1 ]; then
    ( cd "$(dirname "$MAIN")" && timeout 10 "$WORK/a.out" < /dev/null > "$WORK/out.txt" 2>&1 )
    RUN_RC=$?
  fi
fi

build_ok() { [ "$BUILD_OK" -eq 1 ]; }
ran_ok()   { [ "$RUN_RC" -eq 0 ] && [ -s "$WORK/out.txt" ]; }
DATELINES="$(grep -cE ':[[:space:]]*(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.[[:space:]]*[0-9]+' "$WORK/out.txt")"
date_ok()  { [ "${DATELINES:-0}" -ge 3 ]; }
grep -v '^[[:space:]]*#' "$M" | grep -o '"[^"]*"' | sed 's/^"//; s/"$//' | grep -v '\\' | grep -v '^$' | sort -u > "$WORK/lits.txt"
lits_ok() {
  [ -s "$WORK/lits.txt" ] || return 1
  while IFS= read -r l; do grep -qF -- "$l" "$WORK/out.txt" || return 1; done < "$WORK/lits.txt"
}

item 5 "컴파일 성공 (g++ -std=c++17)" build_ok
if [ "$BUILD_OK" -eq 0 ] && [ -n "$LOG" ] && { [ -z "$MODE" ] || [ "$MODE" -eq "$BUILD_FIRST" ]; }; then
  printf '%s\n' "$LOG" | head -n 8 | sed 's/^/        | /'
fi
item 2 "정상 실행 (종료코드 0, 출력 있음)" ran_ok
item 2 "holiday 3개 이상이 '이름: 월. 일' 형식으로 출력" date_ok
item 1 "main.cpp 에 넣은 문자열(그룹명/휴일명)이 출력에 모두 나타남" lits_ok

# ---------------------------------------------------------------------
if [ -n "$MODE" ]; then
  [ "$FOUND" -eq 1 ] || { echo "항목 번호 범위 오류: $MODE (1~$IDX)"; exit 2; }
  exit "$TARGET"
fi
echo "===================================="
echo "총점: $SCORE / 100"
echo "Points $SCORE/100"
exit 0
