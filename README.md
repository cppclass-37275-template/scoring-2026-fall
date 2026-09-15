# scoring

## 📢 안내
- 📟터미널에서 다음 명령어로 💯채점 스크립트를 실행해 볼 수 있습니다.
```
curl -fsSL https://raw.githubusercontent.com/cppclass-37275-template/scoring/main/scoring.sh -o scoring.sh
chmod +x scoring.sh
g++ main.cpp -o main
./scoring.sh  
```

## 📌참고
- 📥`curl -fsSL ...`: 서버에서 채점 스크립트 파일 다운로드
   - 🌐 `curl [URL]` : 해당 주소의 웹 페이지 데이터 가져오기
- `chmod +x scoring.sh`: scoring.sh에 대해 실행(eXecute) 가능한 권한을 추가(+)
   - .sh: Unix 계열 운영체제에서 사용되는 쉘 스크립트(Shell Script) 파일
      - 텍스트 기반의 명령어들을 묶어 쉘(Terminal)에서 한 번에 실행
