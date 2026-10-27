#!/usr/bin/env bash
# =====================================================================
#  scoring5.sh  -  과제5 실습 자동채점 (총 20점)
#
#  사용법
#    bash scoring5.sh             전체 채점 (항목별 결과 + 총점)
#    bash scoring5.sh <항목ID>    해당 항목만 채점. 만점이면 exit 0, 아니면 exit 1
#    bash scoring5.sh list        항목 ID / 배점 목록
#
#  환경변수
#    SRC_DIR    채점할 디렉터리 (기본: 현재 디렉터리)
#    CLASS1_H   클래스1 헤더 경로를 직접 지정 (자동 탐지가 틀렸을 때)
#    CLASS3_H   클래스3 헤더 경로를 직접 지정
#
#  필요 도구: bash, perl, grep, awk, g++
#
#  클래스1 / 클래스3 의 이름과 파일명은 학생마다 다르므로
#  "다른 헤더의 클래스를 상속하는 클래스"를 찾아 클래스3,
#  그 부모 클래스를 클래스1 로 자동 탐지한다.
# =====================================================================
set -u
export LC_ALL=C

SRC_DIR="${SRC_DIR:-.}"
cd "$SRC_DIR" 2>/dev/null || { echo "SRC_DIR($SRC_DIR)로 이동할 수 없습니다."; exit 2; }
SRC_ABS="$(pwd)"
for _c in perl grep awk g++; do
  command -v "$_c" >/dev/null 2>&1 || { echo "필요한 도구가 없습니다: $_c"; exit 2; }
done
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ---------------------------------------------------------------------
#  perl 보조 도구 (주석 제거, 중괄호 짝 맞추기, 멤버/생성자/함수 본문 추출)
# ---------------------------------------------------------------------
cat > "$T/h.pl" <<'PERL'
use strict; use warnings;
my ($cmd, @a) = @ARGV;
my $t = '';
if ($cmd ne 'detect') { local $/; my $in = <STDIN>; $t = defined $in ? $in : ''; }

sub strip_c {
  my ($s, $blank) = @_;
  $s =~ s{("(?:\\.|[^"\\\n])*")|('(?:\\.|[^'\\\n])*')|/\*.*?\*/|//[^\n]*}{
      defined $1 ? ($blank ? '""' : $1) : defined $2 ? ($blank ? "''" : $2) : ' '
  }gse;
  return $s;
}
sub match_close {
  my ($s, $i, $o, $c) = @_;
  my $d = 0; my $n = length $s;
  for (my $j = $i; $j < $n; $j++) {
    my $ch = substr($s, $j, 1);
    if ($ch eq $o) { $d++ } elsif ($ch eq $c) { $d--; return $j if $d == 0 }
  }
  return -1;
}
sub classbody {
  my ($cls) = @_;
  while ($t =~ /\b(class|struct)\s+\Q$cls\E\b[^;{]*\{/g) {
    my $k = $1; my $o = $+[0] - 1;
    my $e = match_close($t, $o, '{', '}');
    return ($k, substr($t, $o + 1, $e - $o - 1)) if $e > 0;
  }
  return ();
}

if ($cmd eq 'strip')  { print strip_c($t, 0); exit 0; }
if ($cmd eq 'blank')  { print strip_c($t, 1); exit 0; }

if ($cmd eq 'firstclass') {
  print $1 if $t =~ /\b(?:class|struct)\s+(\w+)\s*(?:final\s*)?(?::[^;{]*)?\{/;
  exit 0;
}

# 다른 헤더의 클래스를 상속하는 클래스 찾기 -> "클래스3파일 클래스3 클래스1파일 클래스1"
if ($cmd eq 'detect') {
  my (%def, %bases, @order);
  for my $f (@a) {
    open(my $fh, '<', $f) or next;
    my $s = do { local $/; <$fh> }; close $fh;
    $s = strip_c($s, 1);
    while ($s =~ /\b(?:class|struct)\s+(\w+)\s*(?:final\s*)?(:[^;{]*)?\{/g) {
      my ($n, $b) = ($1, $2);
      next if exists $def{$n};
      $def{$n} = $f; push @order, $n;
      my @bs;
      if (defined $b) {
        $b =~ s/^://;
        for my $p (split /,/, $b) {
          $p =~ s/\b(?:public|protected|private|virtual)\b//g;
          $p =~ s/<.*//s; $p =~ s/\s+//g;
          push @bs, $1 if $p =~ /(\w+)$/;
        }
      }
      $bases{$n} = \@bs;
    }
  }
  for my $n (@order) {
    for my $b (@{ $bases{$n} }) {
      if (exists $def{$b} && $def{$b} ne $def{$n}) { print "$def{$n} $n $def{$b} $b\n"; exit 0; }
    }
  }
  exit 0;
}

# namespace X { ... } 블록 (std 제외)
if ($cmd eq 'ns') {
  while ($t =~ /\bnamespace\s+(\w+)\s*\{/g) {
    my $name = $1; my $o = $+[0] - 1;
    my $e = match_close($t, $o, '{', '}');
    next if $e < 0 || $name eq 'std';
    print "\@\@NS $name\n", substr($t, $o + 1, $e - $o - 1), "\n\@\@END\n";
  }
  exit 0;
}

# 이름이 정규식과 일치하는 함수의 "정의" 본문들
if ($cmd eq 'body') {
  my $re = $a[0];
  while ($t =~ /(?<![\w~])(?:$re)\s*\(/g) {
    my $p = $+[0] - 1;
    my $e = match_close($t, $p, '(', ')'); next if $e < 0;
    my $rest = substr($t, $e + 1, 300);
    if ($rest =~ /^\s*(?:(?:const|noexcept|override|final)\b\s*)*(?:->[\w:<>\s\*&]+?)?\s*\{/) {
      my $o = $e + 1 + $+[0] - 1;
      my $c = match_close($t, $o, '{', '}'); next if $c < 0;
      print substr($t, $o + 1, $c - $o - 1), "\n\@\@END\n";
    }
  }
  exit 0;
}

# 클래스 안의 멤버변수 이름 (접근지정자별) -> "이름<TAB>초기값유무"
if ($cmd eq 'members') {
  my ($cls, $want) = @a;
  my ($kind, $b) = classbody($cls);
  exit 0 unless defined $b;
  my $acc = ($kind eq 'struct') ? 'public' : 'private';
  my (@items, $cur, $d); $cur = ''; $d = 0;
  for my $ch (split //, $b) {
    if    ($ch eq '{') { $d++; $cur .= $ch }
    elsif ($ch eq '}') { $d--; $cur .= $ch; if ($d == 0) { push @items, $cur; $cur = '' } }
    elsif ($ch eq ';' && $d == 0) { push @items, $cur; $cur = '' }
    else  { $cur .= $ch }
  }
  push @items, $cur if $cur =~ /\S/;
  for my $it (@items) {
    while ($it =~ s/^\s*(public|protected|private)\s*:(?!:)\s*//) { $acc = $1 }
    $it =~ s/^\s+|\s+$//g;
    next if $it eq '';
    my ($head, $sep) = $it =~ /^([^=({]*)(.?)/s;
    next if $sep eq '(';
    next if $head =~ /^\s*(?:friend|typedef|using|enum|class|struct|template|virtual|explicit|operator|static_assert|return)\b/;
    next unless $head =~ /^\s*(\S.*?[\s\*&])(\w+)\s*(?:\[[^\]]*\]\s*)*$/s;
    my ($type, $name) = ($1, $2);
    next unless $type =~ /\w/;
    my $init = ($sep eq '=' || $sep eq '{') ? 1 : 0;
    print "$name\t$init\n" if $acc eq $want;
  }
  exit 0;
}

# 생성자 정의: 매개변수 / 초기화 리스트 / 본문
if ($cmd eq 'ctor') {
  my $cls = $a[0];
  my $re = qr/
    (?<![\w~])\Q$cls\E\s*(?<params>(?&paren))
    \s*(?::\s*(?<init>(?:[\w:]+(?:<[^<>]*>)?\s*(?:(?&paren)|(?&brace))\s*,?\s*)+))?
    \s*(?<body>(?&brace))
    (?(DEFINE)
      (?<paren>\((?:[^()]++|(?&paren))*\))
      (?<brace>\{(?:[^{}]++|(?&brace))*\})
    )
  /x;
  while ($t =~ /$re/g) {
    my $init = defined $+{init} ? $+{init} : '';
    print "\@\@PARAMS\n$+{params}\n\@\@INIT\n$init\n\@\@BODY\n$+{body}\n\@\@END\n";
  }
  exit 0;
}
PERL
pl() { perl "$T/h.pl" "$@"; }

# ---------------------------------------------------------------------
#  공통 함수
# ---------------------------------------------------------------------
S='[[:space:]]*'
S1='[[:space:]]+'
NSID='[A-Za-z][A-Za-z_]*[0-9]{4,}'          # 이름학번 (예: KimPro3727500)

flat()  { tr '\r\n\t' '   ' | tr -s ' '; }
has()   { printf '%s' "$2" | grep -Eq -- "$1"; }
hasi()  { printf '%s' "$2" | grep -Eiq -- "$1"; }
no()    { ! has "$@"; }
ns_names()     { pl ns < "$1" | sed -n 's/^@@NS //p'; }
ns_has_class() { pl ns < "$1" | grep -Eq "(class|struct)[[:space:]]+$2([^A-Za-z0-9_]|\$)"; }

# ---------------------------------------------------------------------
#  클래스1 / 클래스3 / main.cpp 자동 탐지
# ---------------------------------------------------------------------
mapfile -t HEADERS < <(find . -maxdepth 2 -type f -name '*.h' \
    -not -path './.git/*' -not -path './.github/*' -not -path './tests/*' \
    | sed 's|^\./||' | sort)

C1_H="${CLASS1_H:-}"; C3_H="${CLASS3_H:-}"; C1=""; C3=""
if [[ -z $C1_H || -z $C3_H ]] && ((${#HEADERS[@]} > 0)); then
  d3h=""; d3=""; d1h=""; d1=""
  read -r d3h d3 d1h d1 < <(pl detect "${HEADERS[@]}" </dev/null)
  if [[ -n $d3h ]]; then
    [[ -z $C3_H ]] && { C3_H="$d3h"; C3="$d3"; }
    [[ -z $C1_H ]] && { C1_H="$d1h"; C1="$d1"; }
  else
    # 상속을 못 찾았을 때: 파일명에 3 / 1 이 들어간 헤더를 사용
    for h in "${HEADERS[@]}"; do
      b="$(basename "$h")"
      [[ -z $C3_H && $b == *3* ]] && C3_H="$h"
      [[ -z $C1_H && $b == *1* ]] && C1_H="$h"
    done
  fi
fi
[[ -n $C1_H && ! -f $C1_H ]] && C1_H=""
[[ -n $C3_H && ! -f $C3_H ]] && C3_H=""
[[ -n $C1_H && -z $C1 ]] && C1="$(pl strip < "$C1_H" | pl blank | pl firstclass)"
[[ -n $C3_H && -z $C3 ]] && C3="$(pl strip < "$C3_H" | pl blank | pl firstclass)"

MAIN_CPP=""
if [[ -f main.cpp ]]; then MAIN_CPP="main.cpp"
else MAIN_CPP="$(grep -lE '(^|[^A-Za-z0-9_])main[[:space:]]*\(' ./*.cpp 2>/dev/null | head -1 | sed 's|^\./||')"; fi

prep() { # 파일 접두어  -> $T/접두어.txt(주석제거) $T/접두어s.txt(주석+문자열내용 제거)
  if [[ -n $2 && -f $2 ]]; then
    pl strip < "$2" > "$T/$1.txt"; pl blank < "$2" > "$T/${1}s.txt"
  else : > "$T/$1.txt"; : > "$T/${1}s.txt"; fi
}
prep c1 "$C1_H"; prep c3 "$C3_H"; prep main "$MAIN_CPP"
F1="$(flat < "$T/c1.txt")";  F1S="$(flat < "$T/c1s.txt")"
F3="$(flat < "$T/c3.txt")";  F3S="$(flat < "$T/c3s.txt")"
FM="$(flat < "$T/main.txt")"; FMS="$(flat < "$T/mains.txt")"

# ---------------------------------------------------------------------
#  채점 프레임
# ---------------------------------------------------------------------
SUBS=(); NOTES=(); TOTAL=0
LAST_OK=0; LAST_N=0
sub()  { SUBS+=("$2|$1"); }                                   # sub "설명" 0|1
chk()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then sub "$d" 1; else sub "$d" 0; fi; }
note() { NOTES+=("$1"); }
need() { [[ -n "$1" ]] && return 0; sub "$2" 0; return 1; }   # need 값 "없을 때 메시지"

finish() { # id 제목 배점
  local id="$1" title="$2" max="$3" n=${#SUBS[@]} ok=0 s earned mark
  for s in "${SUBS[@]+"${SUBS[@]}"}"; do [[ ${s%%|*} == 1 ]] && ok=$((ok + 1)); done
  earned=0; (( n > 0 && ok == n )) && earned="$max"   # 항목 단위 정수 채점 (일부만 충족하면 0점)
  TOTAL=$(( TOTAL + earned ))
  mark="[실패]"
  if   (( n > 0 && ok == n )); then mark="[통과]"
  elif (( ok > 0 ));           then mark="[부분]"; fi
  printf '%s %-10s %s : %s / %s\n' "$mark" "$id" "$title" "$earned" "$max"
  for s in "${SUBS[@]+"${SUBS[@]}"}"; do [[ ${s%%|*} == 0 ]] && echo "           - 미충족: ${s#*|}"; done
  for s in "${NOTES[@]+"${NOTES[@]}"}"; do echo "           * $s"; done
  LAST_OK=$ok; LAST_N=$n
}

# ---------------------------------------------------------------------
#  항목 정의  (ID | 제목 | 배점)  -> 20항목 x 1점 = 20점 (Classroom 정수 점수용)
# ---------------------------------------------------------------------
ITEMS=(
  "c1_file|클래스1.h 존재|1"
  "c1_ns_using|클래스1.h namespace(이름학번) 사용, using 없음|1"
  "c1_protected|클래스1.h protected 사용|1"
  "c1_input|클래스1 input(istream&, 기본값 cin)|1"
  "c1_print|클래스1 print(ostream&, 기본값 cout, 채움문자/폭)|1"
  "c1_ops|클래스1 입출력연산자 >> (input), << (print)|1"
  "c3_file|클래스3.h 존재 + 클래스1 public 상속|1"
  "c3_ns_using|클래스3.h namespace(이름학번) 사용, using 없음|1"
  "c3_private|클래스3 private 멤버변수|1"
  "c3_test|클래스3 test 멤버함수(조건 불만족 시 종료)|1"
  "c3_ctor|클래스3 생성자|1"
  "c3_getset|클래스3 get/set 접근함수|1"
  "c3_print|클래스3 print 재정의|1"
  "c3_ops|클래스3 입출력연산자 <<, >>|1"
  "io_file|클래스3io.txt 존재|1"
  "compile|컴파일 및 실행|1"
  "parsing|main.cpp parsing클래스3 함수|1"
  "main_obj|main: 객체1(set, print), 객체2(<< 출력)|1"
  "main_sstream|main: stringstream 처리|1"
  "main_fstream|main: fstream 처리|1"
)

# 합쳐진 항목 (세부 조건은 아래 개별 함수를 순서대로 실행)
item_c1_ns_using() { item_c1_ns; item_c1_using; }
item_c1_ops()      { item_c1_in_op; item_c1_out_op; }
item_c3_ns_using() { item_c3_ns; item_c3_using; }
item_c3_ops()      { item_c3_out_op; item_c3_in_op; }
item_main_obj()    { item_main_obj1; item_main_obj2; }

# ---------------- 클래스1 ----------------
item_c1_file() {
  chk "클래스1 헤더 파일(.h)을 찾을 수 없음" test -n "$C1_H"
}
item_c1_ns() {
  need "$C1_H" "클래스1 헤더 없음" || return
  chk "namespace 블록을 사용" test -n "$(ns_names "$T/c1.txt")"
  chk "namespace 이름이 '이름+학번' 형태 (예: KimPro3727500)" \
      bash -c "grep -Eq '^$NSID\$' <<<\"\$1\"" _ "$(ns_names "$T/c1.txt")"
  chk "클래스1 정의가 namespace 안에 있음" ns_has_class "$T/c1.txt" "$C1"
}
item_c1_using() {
  need "$C1_H" "클래스1 헤더 없음" || return
  chk "헤더에 using namespace / using std:: 가 없음" no 'using[[:space:]]+(namespace|std[[:space:]]*::)' "$F1S"
}
item_c1_protected() {
  need "$C1_H" "클래스1 헤더 없음" || return
  chk "protected: 접근지정자 사용" has 'protected[[:space:]]*:' "$F1S"
  chk "protected 영역에 멤버변수가 있음" test -n "$(pl members "$C1" protected < "$T/c1s.txt")"
}
item_c1_input() {
  need "$C1_H" "클래스1 헤더 없음" || return
  chk "input 함수가 있음" has "(^|[^A-Za-z0-9_])input${S}\(" "$F1S"
  chk "input 매개변수 std::istream& , 기본값 std::cin" \
      has "(^|[^A-Za-z0-9_])input${S}\(([^()]|\([^()]*\))*(std::)?istream${S}&[^()]*=${S}(std::)?cin" "$F1S"
}
item_c1_in_op() {
  need "$C1_H" "클래스1 헤더 없음" || return
  local b; b="$(pl body 'operator\s*>>' < "$T/c1s.txt" | flat)"
  chk "operator>> 가 정의됨" test -n "$b"
  chk "operator>> 안에서 input 함수 호출" has "(^|[^A-Za-z0-9_])input${S}\(" "$b"
}
item_c1_print() {
  need "$C1_H" "클래스1 헤더 없음" || return
  local b; b="$(pl body 'print' < "$T/c1s.txt" | flat)"; [[ -z $b ]] && b="$F1S"
  chk "print 함수가 있음" has "(^|[^A-Za-z0-9_])print${S}\(" "$F1S"
  chk "print 매개변수 std::ostream& , 기본값 std::cout" \
      has "(^|[^A-Za-z0-9_])print${S}\(([^()]|\([^()]*\))*(std::)?ostream${S}&[^()]*=${S}(std::)?cout" "$F1S"
  chk "공백채움문자 설정 (setfill 또는 fill())" has "setfill|\.fill${S}\(" "$b"
  chk "출력폭 설정 (setw 또는 width())" has "setw|\.width${S}\(" "$b"
}
item_c1_out_op() {
  need "$C1_H" "클래스1 헤더 없음" || return
  local b; b="$(pl body 'operator\s*<<' < "$T/c1s.txt" | flat)"
  chk "operator<< 가 정의됨" test -n "$b"
  chk "operator<< 안에서 print 함수 호출" has "(^|[^A-Za-z0-9_])print${S}\(" "$b"
}

# ---------------- 클래스3 ----------------
item_c3_file() {
  chk "클래스3 헤더 파일(.h)을 찾을 수 없음" test -n "$C3_H"
  need "$C3_H" "클래스3 헤더 없음" || return
  local base; base="$(basename "${C1_H:-none}" | sed 's/[][\.*^$]/\\&/g')"
  chk "클래스1 헤더를 #include" has "#${S}include${S}\"([^\"]*/)?${base}\"" "$F3"
  chk "클래스1을 public 으로 상속" \
      has "(class|struct)${S1}${C3}${S}(final${S})?:${S}public${S1}([A-Za-z0-9_]+${S}::${S})*${C1}([^A-Za-z0-9_]|\$)" "$F3S"
}
item_c3_ns() {
  need "$C3_H" "클래스3 헤더 없음" || return
  chk "namespace 블록을 사용" test -n "$(ns_names "$T/c3.txt")"
  chk "namespace 이름이 '이름+학번' 형태 (예: KimPro3727500)" \
      bash -c "grep -Eq '^$NSID\$' <<<\"\$1\"" _ "$(ns_names "$T/c3.txt")"
  chk "클래스3 정의가 namespace 안에 있음" ns_has_class "$T/c3.txt" "$C3"
}
item_c3_using() {
  need "$C3_H" "클래스3 헤더 없음" || return
  chk "헤더에 using namespace / using std:: 가 없음" no 'using[[:space:]]+(namespace|std[[:space:]]*::)' "$F3S"
}
item_c3_private() {
  need "$C3_H" "클래스3 헤더 없음" || return
  chk "private 멤버변수가 있음" test -n "$(pl members "$C3" private < "$T/c3s.txt")"
}
item_c3_test() {
  need "$C3_H" "클래스3 헤더 없음" || return
  local b; b="$(pl body '\w*[Tt]est\w*' < "$T/c3s.txt" | flat)"
  chk "test 멤버함수가 정의됨 (이름에 test 포함)" test -n "$b"
  chk "조건 검사 (if 또는 assert)" has "(^|[^A-Za-z0-9_])(if${S}\(|assert${S}\()" "$b"
  chk "조건이 맞지 않으면 프로그램 종료 (exit/abort/terminate)" \
      has "(^|[^A-Za-z0-9_])(std::)?(exit|abort|terminate|quick_exit|assert)${S}\(" "$b"
}
item_c3_ctor() {
  need "$C3_H" "클래스3 헤더 없음" || return
  local ct pr in bd mem nm iv all=1
  ct="$(pl ctor "$C3" < "$T/c3s.txt")"
  cp() { awk -v w="@@$1" '/^@@(PARAMS|INIT|BODY|END)$/ {cur=$0; next} cur==w {print}' <<<"$ct" | flat; }
  pr="$(cp PARAMS)"; in="$(cp INIT)"; bd="$(cp BODY)"
  mem="$(pl members "$C3" private < "$T/c3s.txt")"
  chk "생성자가 정의됨" test -n "$ct"
  chk "기본값 설정 (기본 인자 또는 매개변수 없는 생성자)" \
      bash -c "grep -Eq '=|^ *\( *\) *\$' <<<\"\$1\"" _ "$pr"
  chk "초기화 리스트에서 클래스1 생성자 호출" \
      has "(^|[^A-Za-z0-9_:])([A-Za-z0-9_]+${S}::${S})*${C1}${S}[({]" "$in"
  chk "생성자에서 test 멤버함수 호출" has "[Tt]est[A-Za-z0-9_]*${S}\(" "$in $bd"
  [[ -z $mem ]] && all=0
  while IFS=$'\t' read -r nm iv; do
    [[ -z $nm ]] && continue
    if [[ $iv == 1 ]] || has "(^|[^A-Za-z0-9_])${nm}${S}(\(|\{|=|\[)" "$in $bd"; then :; else all=0; fi
  done <<<"$mem"
  sub "모든 private 멤버변수를 생성자에서 초기화" "$all"
}
item_c3_getset() {
  need "$C3_H" "클래스3 헤더 없음" || return
  local mem nm base g=1 s=1
  mem="$(pl members "$C3" private < "$T/c3s.txt" | cut -f1)"
  [[ -z $mem ]] && { g=0; s=0; }
  while read -r nm; do
    [[ -z $nm ]] && continue
    base="$(sed -E 's/^m_//; s/^_+//; s/_+$//' <<<"$nm")"
    hasi "(^|[^A-Za-z0-9_])get_?[A-Za-z0-9_]*${base}${S}\(" "$F3S" || g=0
    hasi "(^|[^A-Za-z0-9_])set_?[A-Za-z0-9_]*${base}${S}\(" "$F3S" || s=0
  done <<<"$mem"
  sub "모든 private 멤버변수에 대한 get 함수" "$g"
  sub "모든 private 멤버변수에 대한 set 함수" "$s"
}
item_c3_print() {
  need "$C3_H" "클래스3 헤더 없음" || return
  local b mem nm used=0
  b="$(pl body 'print' < "$T/c3s.txt" | flat)"
  mem="$(pl members "$C3" private < "$T/c3s.txt" | cut -f1)"
  chk "print 함수가 클래스3에 정의됨" test -n "$b"
  chk "print 매개변수 std::ostream& , 기본값 std::cout" \
      has "(^|[^A-Za-z0-9_])print${S}\(([^()]|\([^()]*\))*(std::)?ostream${S}&[^()]*=${S}(std::)?cout" "$F3S"
  while read -r nm; do
    [[ -z $nm ]] && continue
    has "(^|[^A-Za-z0-9_])${nm}([^A-Za-z0-9_]|\$)" "$b" && used=1
  done <<<"$mem"
  sub "print 에서 클래스3에서 추가한 멤버를 출력" "$used"
}
item_c3_out_op() {
  need "$C3_H" "클래스3 헤더 없음" || return
  local b; b="$(pl body 'operator\s*<<' < "$T/c3s.txt" | flat)"
  chk "operator<< 가 클래스3 객체를 매개변수로 정의됨" \
      has "operator${S}<<${S}\(([^()]|\([^()]*\))*[^A-Za-z0-9_]${C3}${S}&" "$F3S"
  chk "operator<< 안에서 print 호출(또는 멤버 출력)" has "print${S}\(|<<" "$b"
}
item_c3_in_op() {
  need "$C3_H" "클래스3 헤더 없음" || return
  local b; b="$(pl body 'operator\s*>>' < "$T/c3s.txt" | flat)"
  chk "operator>> 가 클래스3 객체를 매개변수로 정의됨" \
      has "operator${S}>>${S}\(([^()]|\([^()]*\))*[^A-Za-z0-9_]${C3}${S}&" "$F3S"
  chk "operator>> 안에서 input 호출(또는 >> 로 읽기)" has "input${S}\(|>>" "$b"
}

# ---------------- 파일 / 컴파일 ----------------
IO_FILE=""
[[ -n $C3 && -f "${C3}io.txt" ]] && IO_FILE="${C3}io.txt"
[[ -z $IO_FILE ]] && IO_FILE="$(ls ./*io.txt 2>/dev/null | head -1 | sed 's|^\./||')"
item_io_file() {
  chk "${C3:-클래스3}io.txt 파일이 있음" test -f "${C3}io.txt"
  chk "파일에 데이터가 들어 있음" test -s "${IO_FILE:-/nonexistent}"
}
item_compile() {
  need "$MAIN_CPP" "main.cpp 없음" || return
  local rd="$T/run" rc
  mkdir -p "$rd"
  (cd "$SRC_ABS" && tar --exclude=.git -cf - .) | (cd "$rd" && tar -xf -)
  if (cd "$rd" && timeout 120 g++ -std=c++17 -I. "$MAIN_CPP" -o "$T/a.out") 2> "$T/compile.err"; then
    sub "g++ -std=c++17 컴파일 성공" 1
    (cd "$rd" && timeout 10 "$T/a.out" </dev/null >"$T/run.out" 2>&1); rc=$?
    if (( rc == 0 )); then sub "실행 후 정상 종료" 1
    else sub "실행 후 정상 종료 (종료코드 $rc)" 0; fi
  else
    sub "g++ -std=c++17 컴파일 성공" 0
    sub "실행 후 정상 종료" 0
    while IFS= read -r l; do note "$l"; done < <(grep -E 'error' "$T/compile.err" | head -3)
  fi
}

# ---------------- main.cpp ----------------
MB=""; PDEF=""; PB=""; PNAME=""
if [[ -n $MAIN_CPP ]]; then
  MB="$(pl body 'main' < "$T/mains.txt" | flat)"
  PB="$(pl body 'parsing\w*' < "$T/mains.txt" | flat)"
  PDEF="$(pl ns < "$T/mains.txt" | pl body 'parsing\w*' | flat)"
fi
item_parsing() {
  need "$MAIN_CPP" "main.cpp 없음" || return
  local b="$PDEF"; [[ -z $b ]] && b="$PB"
  chk "namespace(이름학번) 안에 parsing... 함수가 정의됨" test -n "$PDEF"
  chk "리턴 void, 매개변수 iostream& (참조 전달)" \
      has "void${S1}parsing[A-Za-z0-9_]*${S}\(${S}(const${S1})?(std::)?iostream${S}&" "$FMS"
  chk "iostream 에서 클래스3 값을 읽음 (>>)" has ">>|getline|\.read${S}\(" "$b"
  chk "상태플래그 리셋 (clear)" has "\.clear${S}\(" "$b"
  chk "seekp 로 맨 끝 지정 (end)" has "seekp${S}\(([^()]|\([^()]*\))*end" "$b"
  chk "seekp 이후 읽은 값을 iostream 에 씀 (<<)" has "seekp${S}\(([^()]|\([^()]*\))*\).*(<<|\.write${S}\()" "$b"
}

# main 안의 클래스3 객체 선언 목록
OBJ_ALL=(); OBJ_ARG=()
if [[ -n $MB && -n $C3 ]]; then
  while IFS= read -r st; do
    [[ -z $st ]] && continue
    nm="$(sed -E "s/^.*(^|[^A-Za-z0-9_])${C3}[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*\$/\2/" <<<"$st")"
    rest="$(sed -E "s/^.*(^|[^A-Za-z0-9_])${C3}[[:space:]]+${nm}[[:space:]]*//" <<<"$st")"
    OBJ_ALL+=("$nm")
    re_empty='^[({][[:space:]]*[)}]'
    if [[ $rest == \;* || $rest =~ $re_empty ]]; then :; else OBJ_ARG+=("$nm"); fi
  done < <(printf '%s' "$MB" | grep -oE "(^|[^A-Za-z0-9_])([A-Za-z0-9_]+::)*${C3}[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(=|\(|\{|;)[^;]*;")
fi
item_main_obj1() {
  need "$MAIN_CPP" "main.cpp 없음" || return
  local o s=0 p=0
  for o in "${OBJ_ALL[@]+"${OBJ_ALL[@]}"}"; do
    has "(^|[^A-Za-z0-9_])${o}${S}\.${S}set[A-Za-z0-9_]*${S}\(" "$MB" && s=1
    has "(^|[^A-Za-z0-9_])${o}${S}\.${S}print${S}\(" "$MB" && p=1
  done
  sub "main 에서 클래스3 객체를 생성" $(( ${#OBJ_ALL[@]} > 0 ? 1 : 0 ))
  sub "set 함수로 값을 넣음" "$s"
  sub "print 함수로 출력" "$p"
}
item_main_obj2() {
  need "$MAIN_CPP" "main.cpp 없음" || return
  local o c=0
  for o in "${OBJ_ARG[@]+"${OBJ_ARG[@]}"}"; do
    has "cout[^;]*<<${S}${o}${S}(<<|;)" "$MB" && c=1
  done
  sub "값을 넣어(생성자 인자) 클래스3 객체2를 생성" $(( ${#OBJ_ARG[@]} > 0 ? 1 : 0 ))
  sub "출력연산자 << 로 객체2 출력" "$c"
}
item_main_sstream() {
  need "$MAIN_CPP" "main.cpp 없음" || return
  local ss
  ss="$(printf '%s' "$MB" | grep -oE '(^|[^A-Za-z0-9_])(std::)?stringstream[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' | head -1 | awk '{print $NF}')"
  chk "stringstream 객체를 선언" test -n "$ss"
  chk "string 객체를 선언하고 초기화" \
      has "(^|[^A-Za-z0-9_])(std::)?string${S1}[A-Za-z_][A-Za-z0-9_]*${S}(=|\(|\{)" "$MB"
  if [[ -n $ss ]]; then
    chk "stringstream 에 string 을 써줌 (<< 또는 str(...))" \
        has "(^|[^A-Za-z0-9_])${ss}${S}(<<|\.${S}str${S}\(${S}[^) ])|stringstream${S1}${ss}${S}[({=]" "$MB"
    chk "parsing 함수에 stringstream 을 인자로 호출" \
        has "parsing[A-Za-z0-9_]*${S}\(${S}${ss}${S}\)" "$MB"
    chk "표준스트림(cout)으로 stringstream 버퍼 출력 (str() 또는 rdbuf())" \
        has "cout[^;]*(^|[^A-Za-z0-9_])${ss}${S}\.${S}(str|rdbuf)${S}\(" "$MB"
  else
    sub "stringstream 에 string 을 써줌 (<< 또는 str(...))" 0
    sub "parsing 함수에 stringstream 을 인자로 호출" 0
    sub "표준스트림(cout)으로 stringstream 버퍼 출력 (str() 또는 rdbuf())" 0
  fi
}
item_main_fstream() {
  need "$MAIN_CPP" "main.cpp 없음" || return
  local fs
  fs="$(printf '%s' "$MB" | grep -oE '(^|[^A-Za-z0-9_])(std::)?fstream[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' | head -1 | awk '{print $NF}')"
  if [[ -z $fs ]]; then
    sub "fstream 객체를 선언하고 파일을 연결" 0
    sub "파일이 잘 열렸는지 검사 (is_open / ! / fail)" 0
    sub "parsing 함수에 fstream 을 인자로 호출" 0
    return
  fi
  chk "fstream 객체를 선언하고 파일을 연결 (생성자 또는 open)" \
      has "fstream${S1}${fs}${S}[({]${S}[^)} ]|(^|[^A-Za-z0-9_])${fs}${S}\.${S}open${S}\(" "$MB"
  chk "파일이 잘 열렸는지 검사 (is_open / ! / fail)" \
      has "(if|while)${S}\(${S}!?${S}${fs}${S}[)&|]|${fs}${S}\.${S}(is_open|fail|good|bad)${S}\(|!${S}${fs}([^A-Za-z0-9_]|\$)" "$MB"
  chk "parsing 함수에 fstream 을 인자로 호출" \
      has "parsing[A-Za-z0-9_]*${S}\(${S}${fs}${S}\)" "$MB"
}

# ---------------------------------------------------------------------
#  실행
# ---------------------------------------------------------------------
run_item() { # id -> 0(만점) / 1
  local it id title max
  for it in "${ITEMS[@]}"; do
    IFS='|' read -r id title max <<<"$it"
    if [[ $id == "$1" ]]; then
      SUBS=(); NOTES=()
      "item_$id"
      finish "$id" "$title" "$max"
      return $(( LAST_N > 0 && LAST_OK == LAST_N ? 0 : 1 ))
    fi
  done
  echo "알 수 없는 항목: $1  (bash scoring5.sh list 로 확인)"; return 2
}

MODE="${1:-all}"
case "$MODE" in
  list)
    for it in "${ITEMS[@]}"; do IFS='|' read -r id title max <<<"$it"; printf '%-12s %-4s %s\n' "$id" "$max" "$title"; done
    exit 0 ;;
  all)
    echo "===== 과제5 실습 자동채점 ====="
    echo "클래스1 : ${C1:-(탐지 실패)}  (${C1_H:-없음})"
    echo "클래스3 : ${C3:-(탐지 실패)}  (${C3_H:-없음})"
    echo "main    : ${MAIN_CPP:-(없음)}"
    echo "-----------------------------"
    for it in "${ITEMS[@]}"; do IFS='|' read -r id _ _ <<<"$it"; run_item "$id"; done
    MAXSUM="$(for it in "${ITEMS[@]}"; do IFS='|' read -r _ _ m <<<"$it"; echo "$m"; done | awk '{s+=$1} END{printf "%d", s}')"
    echo "-----------------------------"
    echo "총점: $TOTAL / $MAXSUM"
    exit 0 ;;
  *)
    run_item "$MODE"; exit $? ;;
esac
