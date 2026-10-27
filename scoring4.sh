#!/usr/bin/env bash
# scoring4.sh - 과제4(클래스1DynamicArray: 이름학번 namespace + Rule of Five + vector) 자동채점, 총 20점
#
# 사용법
#   bash scoring4.sh            : 전체 채점 -> 항목별 결과와 총점 출력 (항상 exit 0)
#   bash scoring4.sh <항목ID>   : 해당 항목만 채점 -> 통과 exit 0 / 실패 exit 1  (Classroom 항목별 Run Command용)
#   bash scoring4.sh list       : 항목ID / 배점 / 설명 출력
# 환경변수: GRADE_DIR = 채점할 폴더 (기본 .)
#
# 클래스1 이름은 학생마다 다르므로 '*DynamicArray.h' 파일명(없으면 main.cpp의 include)에서 자동 탐지한다.

ROOT="${GRADE_DIR:-.}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PL="$TMP/check.pl"

# ------------------------------------------------------------------
# 소스 분석용 perl (주석/문자열 제거 후 구조 분석)
# ------------------------------------------------------------------
cat > "$PL" <<'PERL_EOF'
use strict; use warnings;
my ($what, $file, @args) = @ARGV;
local $/;
open(my $fh, '<', $file) or do { print "FAIL: cannot open $file\n"; exit 3 };
my $s = <$fh>; close $fh;
# 주석 제거, 문자열/문자 리터럴 내용 제거
$s =~ s{ ("(?:\\.|[^"\\\n])*") | ('(?:\\.|[^'\\\n])+') | /\*.*?\*/ | //[^\n]* }{ defined($1) ? '""' : defined($2) ? "''" : ' ' }gsex;

sub ok   { print "OK" . (@_ ? " @_" : "") . "\n"; exit 0 }
sub fail { print "FAIL: $_[0]\n"; exit 1 }

my $NSRE  = qr/^[A-Za-z][A-Za-z_]*[0-9]{4,}$/;
my $INIT  = qr/(?::\s*(?:[\w:<>]+\s*(?:\((?:[^()]|\([^()]*\))*\)|\{[^{}]*\})\s*,?\s*)+)?/;

sub enclosing_ns {
  my ($pos) = @_;
  my $head = substr($s, 0, $pos);
  my @st;
  while ($head =~ /\G(?:namespace\s+(\w+)\s*\{|(\{)|(\})|\w+|\s+|.)/gcs) {
    if (defined $1) { push @st, $1 } elsif (defined $2) { push @st, '' } elsif (defined $3) { pop @st }
  }
  return grep { length } @st;
}
sub body_at {
  my ($i) = @_; my $d = 1; my $st = $i; my $n = length $s;
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq '{') { $d++ } elsif ($c eq '}') { $d--; last if $d == 0 }
    $i++;
  }
  return substr($s, $st, $i - $st);
}
sub find_body { my ($re) = @_; return undef unless $s =~ /$re/; return body_at($+[0]); }
sub find_text { my ($re) = @_; return undef unless $s =~ /$re/; my ($a,$b)=($-[0],$+[0]); return substr($s,$a,$b-$a) . body_at($b); }
sub find_after { my ($str,$re,$from) = @_; pos($str) = $from; return ($str =~ /$re/g) ? $-[0] : -1; }
sub stmt_start { my ($str,$p) = @_; return substr($str,0,$p) =~ /(?:^|[;{}):]|\belse\b|\bdo\b)\s*$/ ? 1 : 0; }
sub printed { my ($b,$w) = @_; return ($b =~ /(?:cout|printf)[^;]*\b$w\s*\(\s*\)/ || $b =~ /=\s*[\w.]+\s*\.\s*$w\s*\(\s*\)\s*;/) ? 1 : 0; }

if ($what eq 'strip')   { print $s; exit 0 }
if ($what eq 'nousing') { $s =~ /\busing\b/ and fail("헤더파일에 using 사용 (using 지시자 대신 네임스페이스 지정자 std:: 사용)"); ok() }

if ($what eq 'classns') {
  my ($cls) = @args;
  $s =~ /\b(?:class|struct)\s+\Q$cls\E\b\s*(?:final\s*)?(?::[^;{]*)?\{/ or fail("class $cls 정의를 찾을 수 없음");
  my @ns = enclosing_ns($-[0]);
  @ns or fail("클래스가 namespace 안에 정의되어 있지 않음");
  $ns[-1] =~ $NSRE or fail("namespace '$ns[-1]' 이(가) 이름학번 형식이 아님 (예: KimPro3727500)");
  ok("ns=$ns[-1]");
}

if ($what eq 'arrdef') {
  my ($arr, $ns) = @args; my $A = quotemeta $arr;
  $s =~ /\b(?:class|struct)\s+$A\b\s*(?:final\s*)?(?::[^;{]*)?\{/ or fail("class $arr 정의를 찾을 수 없음");
  my @ns = enclosing_ns($-[0]);
  my $okns = $ns ? scalar(grep { $_ eq $ns } @ns) : scalar(grep { $_ =~ $NSRE } @ns);
  $okns or fail("클래스가 " . ($ns ? "'$ns'" : "이름학번") . " namespace 안에 정의되어 있지 않음");
  $s =~ /\b$A\s*::\s*~?\s*(?:\w+|operator)/ and fail("멤버함수를 클래스 밖에서 정의함 (모두 클래스 안에 인라인으로 구현해야 함)");
  ok();
}

if ($what eq 'sections') {
  my ($arr, $out) = @args; my $A = quotemeta $arr;
  $s =~ /\b(class|struct)\s+$A\b\s*(?:final\s*)?(?::[^;{]*)?\{/ or fail("class $arr 정의를 찾을 수 없음");
  my $kw = $1; my $i = $+[0];
  my $acc = ($kw eq 'struct') ? 'public' : 'private';
  my %buf = (private => '', public => '', protected => '');
  my ($seg, $d, $n) = ('', 1, length $s);
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq '{') { $d++ }
    elsif ($c eq '}') { $d--; last if $d == 0 }
    elsif ($c eq ':' && $d == 1 && substr($s,$i+1,1) ne ':' && substr($s,$i-1,1) ne ':') {
      if ($seg =~ /\b(public|private|protected)\s*$/) {
        my $a = $1; $seg =~ s/\b(?:public|private|protected)\s*$//;
        $buf{$acc} .= $seg; $seg = ''; $acc = $a; $i++; next;
      }
    }
    $seg .= $c; $i++;
  }
  $buf{$acc} .= $seg;
  for my $k (qw(private public protected)) { open(my $o, '>', "$out/$k.txt") or exit 3; print $o $buf{$k}; close $o }
  ok();
}

if ($what eq 'privn') {
  $s =~ /\bint\s+n\b\s*(?:=|;|,|\{)/ or fail("private 영역에 int형 멤버변수 n 선언이 없음");
  ok();
}
if ($what eq 'privptr') {
  my ($c) = @args;
  $s =~ /\b(?:\w+\s*::\s*)*\Q$c\E\s*\*\s*\w+\s*(?:=|;|,|\{)/ or fail("private 영역에 $c 형을 가리키는 포인터 멤버변수가 없음");
  ok();
}

if ($what eq 'method') {
  my ($kind, $arr, $c) = @args;
  my $A = quotemeta $arr;
  my $C = '(?:\w+\s*::\s*)*' . quotemeta($c);
  my $CONSTREF = qr/(?:const\s+$A\s*&(?!&)|$A\s+const\s*&(?!&))/;
  if ($kind eq 'ctor') {
    while ($s =~ /(?<![~\w:])$A\s*\(((?:[^()]|\([^()]*\))*)\)\s*(?:=\s*default\s*;|(?:noexcept\s*)?$INIT\s*\{)/g) {
      ok() if $1 !~ /$A\s*&/;
    }
    fail("생성자(복사/이동 제외) 정의가 없음");
  }
  if ($kind eq 'dtor') {
    my $b = find_text(qr/~\s*$A\s*\(\s*(?:void)?\s*\)\s*(?:noexcept\s*)?\{/);
    defined $b or fail("소멸자 ~$arr() 인라인 정의가 없음");
    $b =~ /\bdelete\b/ or fail("소멸자에서 동적 메모리를 해제(delete[])하지 않음");
    ok();
  }
  if ($kind eq 'copyctor') {
    my $b = find_text(qr/(?<![~\w:])$A\s*\(\s*$CONSTREF\s*\w*\s*\)\s*(?:noexcept\s*)?$INIT\s*\{/);
    defined $b or fail("복사생성자 $arr(const $arr&) 를 직접 구현해야 함 (= default/delete 불가)");
    $b =~ /\bnew\b|:\s*$A\s*\(|\*\s*this\s*=|operator\s*=/ or fail("복사생성자에서 깊은 복사(new)를 하지 않음");
    ok();
  }
  if ($kind eq 'copyassign') {
    my $b = find_text(qr/\b$A\s*&\s*operator\s*=\s*\(\s*$CONSTREF\s*\w*\s*\)\s*(?:noexcept\s*)?\{/);
    defined $b or fail("복사대입연산자 $arr& operator=(const $arr&) 를 직접 구현해야 함");
    $b =~ /\bnew\b|\bswap\b|\b$A\s+\w+\s*[({]/ or fail("복사대입연산자에서 깊은 복사(new)를 하지 않음");
    ok();
  }
  if ($kind eq 'movector') {
    my $b = find_text(qr/(?<![~\w:])$A\s*\(\s*$A\s*&&\s*\w*\s*\)\s*(?:noexcept\s*)?$INIT\s*\{/);
    defined $b or fail("이동생성자 $arr($arr&&) 를 직접 구현해야 함 (= default/delete 불가)");
    $b =~ /\bnullptr\b|\bNULL\b|\bswap\b|\bexchange\b|=\s*0\b/ or fail("이동생성자에서 원본 포인터를 비우지(nullptr) 않음");
    ok();
  }
  if ($kind eq 'moveassign') {
    my $b = find_text(qr/\b$A\s*&\s*operator\s*=\s*\(\s*$A\s*&&\s*\w*\s*\)\s*(?:noexcept\s*)?\{/);
    defined $b or fail("이동대입연산자 $arr& operator=($arr&&) 를 직접 구현해야 함");
    $b =~ /\bdelete\b|\bswap\b|\bexchange\b/ or fail("이동대입연산자에서 기존 메모리를 해제(delete[])하지 않음");
    $b =~ /\bnullptr\b|\bNULL\b|\bswap\b|\bexchange\b|=\s*0\b/ or fail("이동대입연산자에서 원본 포인터를 비우지(nullptr) 않음");
    ok();
  }
  if ($kind eq 'index') {
    while ($s =~ /$C\s*&\s*operator\s*\[\s*\]\s*\(\s*(?:const\s+)?(?:unsigned\s+|signed\s+)?(?:int|long|short|size_t|std\s*::\s*size_t)\s*\w*\s*\)\s*(?:const\s*)?(?:noexcept\s*)?\{/g) {
      my $p = $-[0];
      my $pre = substr($s, ($p > 8 ? $p - 8 : 0), ($p > 8 ? 8 : $p));
      ok() unless $pre =~ /const\s*$/;
    }
    fail("[] 연산자 오버로딩 $c& operator[](int) 인라인 정의가 없음 (참조 반환 필요)");
  }
  if ($kind eq 'printall') {
    my $b = find_body(qr/[\w:<>&*]+\s+printAll\s*\([^)]*\)\s*(?:const\s*)?(?:noexcept\s*)?\{/);
    defined $b or fail("printAll 함수 인라인 정의가 없음");
    $b =~ /\b(?:for|while)\b/ or fail("printAll에 배열을 순차적으로 출력하는 반복문이 없음");
    $b =~ /cout|printf|puts|<<|(?:\.|->)\s*\w*[Pp]rint\w*\s*\(|\bprint\w*\s*\(/ or fail("printAll에 표준스트림 출력이 없음");
    ok();
  }
  fail("unknown method kind $kind");
}

if ($what eq 'printvec') {
  my ($c, $arr, $ns) = @args; my $A = quotemeta $arr;
  $s =~ /([\w:<>&*]+)\s+(printVector\w*)\s*\(\s*(?:const\s+)?(?:std\s*::\s*)?vector\s*<\s*(?:\w+\s*::\s*)*$A\s*>\s*(?:const\s*)?&?\s*\w*\s*\)\s*\{/
    or fail("printVector${c}DynamicArray(std::vector<$arr>) 함수 정의를 찾을 수 없음");
  my ($ret, $fname, $st, $en) = ($1, $2, $-[0], $+[0]);
  $ret eq 'void' or fail("printVector 함수의 리턴 타입이 void가 아님 ($ret)");
  $fname =~ /^printVector\Q$c\E(?:Dynamic)?Array$/i or fail("함수 이름이 printVector${c}DynamicArray 형식이 아님 ($fname)");
  my @ns = enclosing_ns($st);
  my $okns = $ns ? scalar(grep { $_ eq $ns } @ns) : scalar(grep { $_ =~ $NSRE } @ns);
  $okns or fail("printVector 함수가 이름학번 namespace 안에 정의되어 있지 않음");
  my $b = body_at($en);
  $b =~ /\bfor\s*\(/ or fail("printVector에 for 구문이 없음");
  $b =~ /(?:\.|->)\s*printAll\s*\(/ or fail("printVector에서 원소의 printAll 함수를 호출하지 않음");
  printed($b, 'size')     or fail("printVector에서 size를 출력하지 않음");
  printed($b, 'capacity') or fail("printVector에서 capacity를 출력하지 않음");
  ok();
}

if ($what eq 'main') {
  my ($item, $arr) = @args; my $A = quotemeta $arr;
  my $m = find_body(qr/\bint\s+main\s*\([^)]*\)\s*\{/);
  defined $m or fail("main 함수를 찾을 수 없음");
  my $T = qr/(?:\w+\s*::\s*)*$A/;
  my (@names, %isn);
  while ($m =~ /(?<![\w<>:])$T\s+((?:[^;{}()]|\((?:[^()]|\([^()]*\))*\)|\{[^{}]*\})*);/g) {
    my $d = $1;
    1 while $d =~ s/\((?:[^()]|\([^()]*\))*\)//;
    1 while $d =~ s/\{[^{}]*\}//;
    for my $part (split /,/, $d) {
      if ($part =~ /^\s*[*&]*\s*(\w+)/ && !$isn{$1}) { $isn{$1} = 1; push @names, $1 }
    }
  }

  if ($item == 18) {
    @names >= 3 or fail(sprintf("main에서 %s 객체를 3개 선언해야 함 (현재 %d개)", $arr, scalar @names));
    my ($name, $pos);
    while ($m =~ /\b(\w+)\s*\[[^\]]*\]\s*=(?!=)/g) { if ($isn{$1}) { ($name, $pos) = ($1, $-[0]); last } }
    defined $name or fail("[] 연산자로 객체를 초기화하는 코드(객체1[i] = 값;)가 없음");
    find_after($m, qr/\b\Q$name\E\s*\.\s*printAll\s*\(/, $pos) >= 0 or fail("[] 초기화 후 $name.printAll() 호출이 없음");
    ok();
  }

  if ($item == 19) {
    my ($cl, $cp);
    while ($m =~ /\b(\w+)\s*=\s*(\w+)\s*;/g) {
      my ($l, $r, $p) = ($1, $2, $-[0]);
      if ($isn{$l} && $isn{$r} && $l ne $r && stmt_start($m, $p)) { ($cl, $cp) = ($l, $p); last }
    }
    defined $cp or fail("복사 할당(객체2 = 객체1;) 코드가 없음");
    find_after($m, qr/\b\Q$cl\E\s*\.\s*printAll\s*\(/, $cp) >= 0 or fail("복사 할당 후 $cl.printAll() 호출이 없음");
    my ($mr, $mp);
    pos($m) = 0;
    while ($m =~ /\b(\w+)\s*=\s*(?:std\s*::\s*)?move\s*\(\s*(\w+)\s*\)\s*;/g) {
      my ($l, $r, $p) = ($1, $2, $-[0]);
      if ($isn{$l} && $isn{$r} && stmt_start($m, $p)) { ($mr, $mp) = ($r, $p); last }
    }
    defined $mp or fail("이동 할당(객체3 = std::move(객체2);) 코드가 없음");
    find_after($m, qr/\b\Q$mr\E\s*\.\s*printAll\s*\(/, $mp) >= 0 or fail("이동 할당 후 $mr.printAll() 호출이 없음");
    ok();
  }

  if ($item == 20) {
    $m =~ /(?:std\s*::\s*)?\bvector\s*<\s*(?:\w+\s*::\s*)*$A\s*>\s+(\w+)\s*(?:;|\{|\(|=)/ or fail("$arr 형 std::vector 선언이 없음");
    my ($v, $d) = ($1, $-[0]); my $V = quotemeta $v;
    my $call = qr/\bprintVector\w*\s*\(\s*$V\s*\)/;
    my $c1 = find_after($m, $call, $d);                                         $c1 >= 0 or fail("vector 선언 후 printVector...($v) 호출이 없음");
    my $pc = find_after($m, qr/\b$V\s*\.\s*push_back\s*\(\s*\w+\s*\)/, $c1);    $pc >= 0 or fail("$v.push_back(객체1) 복사 추가 코드가 없음");
    my $c2 = find_after($m, $call, $pc);                                        $c2 >= 0 or fail("복사 push_back 후 printVector...($v) 호출이 없음");
    my $pm = find_after($m, qr/\b$V\s*\.\s*push_back\s*\(\s*(?:std\s*::\s*)?move\s*\(\s*\w+\s*\)\s*\)/, $c2);
                                                                                $pm >= 0 or fail("$v.push_back(std::move(객체1)) 이동 추가 코드가 없음");
    my $c3 = find_after($m, $call, $pm);                                        $c3 >= 0 or fail("이동 push_back 후 printVector...($v) 호출이 없음");
    substr($m, $pm) =~ /move\s*\(\s*(\w+)\s*\)/;
    my $r = $1;
    find_after($m, qr/\b\Q$r\E\s*\.\s*printAll\s*\(/, $c3) >= 0 or fail("마지막에 $r.printAll() 호출이 없음");
    ok();
  }
  fail("unknown main item $item");
}
fail("unknown command $what");
PERL_EOF

# ------------------------------------------------------------------
# 파일 / 이름 탐지
# ------------------------------------------------------------------
find_files() { find "$ROOT" -maxdepth 3 -type f "$@" -not -path '*/.git/*' -not -path '*/.github/*' 2>/dev/null | sort; }
classnames() { perl "$PL" strip "$1" 2>/dev/null | grep -oE '\b(class|struct)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' | awk '{print $2}'; }

ARR_H="$(find_files -iname '*DynamicArray.h' | head -n1)"
MAIN_CPP="$(find_files -name main.cpp | head -n1)"
if [[ -z "$MAIN_CPP" ]]; then
  MAIN_CPP="$(find_files -name '*.cpp' | xargs -r grep -lE '\bint[[:space:]]+main[[:space:]]*\(' 2>/dev/null </dev/null | head -n1)"
fi

C=""
if [[ -n "$ARR_H" ]]; then
  b="$(basename "$ARR_H" .h)"
  C="$(sed -E 's/[Dd]ynamic[Aa]rray$//' <<<"$b")"
fi
if [[ -z "$C" && -n "$MAIN_CPP" ]]; then
  for inc in $(grep -hoE '#include[[:space:]]*"[^"]+\.h"' "$MAIN_CPP" | sed -E 's/.*"([^"]+)"/\1/'); do
    b="$(basename "$inc" .h)"
    [[ "$b" =~ [Aa]rray ]] && continue
    C="$b"; break
  done
fi

CLS_H=""; CLS=""
if [[ -n "$C" ]]; then
  CLS_H="$(find_files -iname "${C}.h" | head -n1)"
fi
if [[ -n "$CLS_H" ]]; then
  names="$(classnames "$CLS_H")"
  CLS="$(grep -ixF "$C" <<<"$names" | head -n1)"
  [[ -z "$CLS" ]] && CLS="$(head -n1 <<<"$names")"
  [[ -z "$CLS" ]] && CLS="$C"
fi

ARR_CLS=""
if [[ -n "$ARR_H" ]]; then
  names="$(classnames "$ARR_H")"
  for cand in "${CLS}DynamicArray" "${C}DynamicArray" "${CLS}Array" "${C}Array"; do
    hit="$(grep -ixF "$cand" <<<"$names" | head -n1)"
    [[ -n "$hit" ]] && { ARR_CLS="$hit"; break; }
  done
  [[ -z "$ARR_CLS" ]] && ARR_CLS="$(grep -iE 'Array' <<<"$names" | head -n1)"
  [[ -z "$ARR_CLS" ]] && ARR_CLS="$(head -n1 <<<"$names")"
fi
[[ -z "$ARR_CLS" ]] && ARR_CLS="${CLS:-$C}DynamicArray"

NS1=""
[[ -n "$CLS_H" ]] && NS1="$(perl "$PL" classns "$CLS_H" "$CLS" 2>/dev/null | sed -n 's/^OK ns=//p')"
EXP_NS="$NS1"
if [[ -z "$EXP_NS" && -n "$ARR_H" ]]; then
  EXP_NS="$(perl "$PL" classns "$ARR_H" "$ARR_CLS" 2>/dev/null | sed -n 's/^OK ns=//p')"
fi

SEC_OK=0; SEC_MSG=""
if [[ -n "$ARR_H" ]]; then
  if perl "$PL" sections "$ARR_H" "$ARR_CLS" "$TMP" >"$TMP/sec.log" 2>&1; then SEC_OK=1
  else SEC_MSG="$(sed 's/^FAIL: //' "$TMP/sec.log")"; fi
fi

# ------------------------------------------------------------------
# 항목 정의 (기본 배점 1점, 바꾸려면 PT[id]=n)
# ------------------------------------------------------------------
IDS=(file_class1 ns_class1 no_using file_array array_ns_inline priv_n priv_ptr
     ctor dtor copy_ctor copy_assign move_ctor move_assign op_index print_all
     compile print_vector main_objs main_assign main_vector)
declare -A PT=()
declare -A DESC=(
  [file_class1]="클래스1.h 파일 존재"
  [ns_class1]="클래스1.h에서 이름학번 namespace 사용"
  [no_using]="헤더파일(2개)에 using 없음 (주석 무시)"
  [file_array]="클래스1DynamicArray.h 파일 존재"
  [array_ns_inline]="클래스1DynamicArray가 같은 이름학번 namespace 안에 정의 + 멤버함수 모두 인라인 구현"
  [priv_n]="private 멤버변수: int형 n"
  [priv_ptr]="private 멤버변수: 클래스1형 포인터"
  [ctor]="생성자"
  [dtor]="소멸자 (동적 메모리 해제)"
  [copy_ctor]="복사생성자 (깊은 복사)"
  [copy_assign]="복사 = 연산자 (깊은 복사)"
  [move_ctor]="이동생성자"
  [move_assign]="이동 = 연산자"
  [op_index]="[] 연산자 오버로딩"
  [print_all]="printAll: 배열을 순차 출력"
  [compile]="컴파일 성공 (main.cpp)"
  [print_vector]="main.cpp: namespace 안 printVector클래스1DynamicArray (void, vector 매개변수, for, printAll, size/capacity 출력)"
  [main_objs]="main: 객체 3개 선언, [] 초기화, 객체1.printAll()"
  [main_assign]="main: 복사 할당 + printAll, 이동 할당 + printAll"
  [main_vector]="main: vector 선언/printVector, push_back 복사/이동 후 printVector, 객체1.printAll()"
)

MSG=""
pl() { OUT="$(perl "$PL" "$@" 2>&1)"; case "$OUT" in OK*) return 0 ;; *) MSG="${OUT#FAIL: }"; return 1 ;; esac; }
need_sec() {
  [[ -n "$ARR_H" ]] || { MSG="클래스1DynamicArray.h 파일 없음"; return 1; }
  [[ $SEC_OK -eq 1 ]] || { MSG="${SEC_MSG:-클래스 정의를 찾을 수 없음}"; return 1; }
}
need_main() { [[ -n "$MAIN_CPP" ]] || { MSG="main.cpp 파일 없음"; return 1; }; }

t_file_class1()  { [[ -n "$CLS_H" ]] && return 0; MSG="클래스1.h 파일을 찾을 수 없음 (클래스1 이름은 ...DynamicArray.h 파일명에서 탐지)"; return 1; }
t_ns_class1()    { [[ -n "$CLS_H" ]] || { MSG="클래스1.h 파일 없음"; return 1; }; pl classns "$CLS_H" "$CLS"; }
t_no_using() {
  [[ -n "$CLS_H" && -n "$ARR_H" ]] || { MSG="두 헤더 파일이 모두 있어야 검사 가능"; return 1; }
  local f
  for f in "$CLS_H" "$ARR_H"; do pl nousing "$f" || { MSG="$(basename "$f"): $MSG"; return 1; }; done
  return 0
}
t_file_array()      { [[ -n "$ARR_H" ]] && return 0; MSG="클래스1DynamicArray.h 파일을 찾을 수 없음"; return 1; }
t_array_ns_inline() { [[ -n "$ARR_H" ]] || { MSG="클래스1DynamicArray.h 파일 없음"; return 1; }; pl arrdef "$ARR_H" "$ARR_CLS" "$EXP_NS"; }
t_priv_n()       { need_sec && pl privn "$TMP/private.txt"; }
t_priv_ptr()     { need_sec && pl privptr "$TMP/private.txt" "$CLS"; }
t_ctor()         { need_sec && pl method "$TMP/public.txt" ctor       "$ARR_CLS" "$CLS"; }
t_dtor()         { need_sec && pl method "$TMP/public.txt" dtor       "$ARR_CLS" "$CLS"; }
t_copy_ctor()    { need_sec && pl method "$TMP/public.txt" copyctor   "$ARR_CLS" "$CLS"; }
t_copy_assign()  { need_sec && pl method "$TMP/public.txt" copyassign "$ARR_CLS" "$CLS"; }
t_move_ctor()    { need_sec && pl method "$TMP/public.txt" movector   "$ARR_CLS" "$CLS"; }
t_move_assign()  { need_sec && pl method "$TMP/public.txt" moveassign "$ARR_CLS" "$CLS"; }
t_op_index()     { need_sec && pl method "$TMP/public.txt" index      "$ARR_CLS" "$CLS"; }
t_print_all()    { need_sec && pl method "$TMP/public.txt" printall   "$ARR_CLS" "$CLS"; }
t_compile() {
  need_main || return 1
  command -v g++ >/dev/null 2>&1 || { MSG="g++ 컴파일러 없음"; return 1; }
  local inc=() d
  for d in "$CLS_H" "$ARR_H" "$MAIN_CPP"; do [[ -n "$d" ]] && inc+=("-I$(dirname "$d")"); done
  if timeout 120 g++ -std=c++17 "${inc[@]}" "$MAIN_CPP" -o "$TMP/a.out" >"$TMP/compile.log" 2>&1; then return 0; fi
  MSG="컴파일 실패: $(grep -m3 'error' "$TMP/compile.log" | tr '\n' ' ' | cut -c1-300)"
  return 1
}
t_print_vector() { need_main && pl printvec "$MAIN_CPP" "$C" "$ARR_CLS" "$EXP_NS"; }
t_main_objs()    { need_main && pl main "$MAIN_CPP" 18 "$ARR_CLS"; }
t_main_assign()  { need_main && pl main "$MAIN_CPP" 19 "$ARR_CLS"; }
t_main_vector()  { need_main && pl main "$MAIN_CPP" 20 "$ARR_CLS"; }

# ------------------------------------------------------------------
# 실행
# ------------------------------------------------------------------
if [[ "${1:-}" == "list" ]]; then
  for id in "${IDS[@]}"; do printf '%-16s %s점  %s\n' "$id" "${PT[$id]:-1}" "${DESC[$id]}"; done
  exit 0
fi

if [[ -n "${1:-}" ]]; then
  id="$1"
  [[ -n "${DESC[$id]:-}" ]] || { echo "알 수 없는 항목: $id (bash scoring4.sh list 로 확인)"; exit 2; }
  if "t_$id"; then echo "[PASS] ${DESC[$id]}"; exit 0
  else echo "[FAIL] ${DESC[$id]} -> $MSG"; exit 1; fi
fi

echo "===== 과제4 자동채점 ====="
echo "클래스1 탐지 : ${CLS:-(없음)}  (${CLS_H:-파일 없음})"
echo "배열 클래스  : ${ARR_CLS}  (${ARR_H:-파일 없음})"
echo "namespace    : ${EXP_NS:-(탐지 실패)}"
echo "main         : ${MAIN_CPP:-파일 없음}"
echo "-----------------------------"
total=0; max=0
for id in "${IDS[@]}"; do
  p="${PT[$id]:-1}"; MSG=""; max=$((max + p))
  if "t_$id"; then
    total=$((total + p)); printf '[PASS] (%d/%d) %s\n' "$p" "$p" "${DESC[$id]}"
  else
    printf '[FAIL] (0/%d) %s\n         -> %s\n' "$p" "${DESC[$id]}" "$MSG"
  fi
done
echo "-----------------------------"
echo "총점: $total / $max"
exit 0