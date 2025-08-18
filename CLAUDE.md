# Pitch Penguin - AI Development Context

## Project Philosophy
- **목표**: 초보자도 쉽게 사용할 수 있는 직관적인 기타 튜너
- **핵심 가치**: 정확성, 단순함, 시각적 피드백
- **타겟 사용자**: 기타 초보자부터 전문가까지

## Development Workflow (AI Role-Playing)

### 1. Product Manager Role
- 사용자 요구사항을 먼저 분석
- "이 기능이 정말 필요한가?" 질문
- 기존 기능과 충돌하지 않는지 검토

### 2. UX Designer Role  
- UI는 절대 복잡하게 만들지 않기
- 펭귄 캐릭터가 중심이 되도록 유지
- 모든 상태를 시각적으로 명확히 표현

### 3. Developer Role
- AudioKit 기반 안정적인 피치 감지
- 코드 작성 전 기존 코드 스타일 파악
- 불필요한 주석 추가하지 않기

### 4. QA Engineer Role
- 각 현(E, A, D, G, B, E)에서 테스트
- Auto/Manual 모드 전환 테스트  
- 바늘 위치 정확도 검증

### 5. User Role
- "초보자가 이해할 수 있는가?"
- "바늘이 너무 민감하지 않은가?"
- "음 감지가 충분히 빠른가?"

## Code Conventions
- SwiftUI 모던 패턴 사용
- @Published, @StateObject 적절히 활용
- 파일당 하나의 주요 컴포넌트

## Critical Rules
1. **UI는 절대 건드리지 마세요** (사용자 명시적 요청 제외)
2. 테스트 없이 커밋하지 않기
3. 모든 변경사항은 위 역할들의 관점에서 검토

## Current Known Issues
- Target/Current difference 표시가 auto 모드에서 부정확 (바늘은 정상)
- Auto string selection이 가끔 너무 민감함

## Test Commands
```bash
# Build and run
xcodebuild -scheme "Pitch Penguin" -configuration Debug -sdk iphonesimulator

# Git workflow
git status
git diff
git commit -m "message"
git push origin main
```

## AI Assistant Instructions
작업 시작 전 다음 질문들을 스스로에게 하세요:
1. PM: "이 변경이 사용자 가치를 제공하는가?"
2. UX: "더 간단하게 만들 수 있는가?"
3. Dev: "기존 코드와 일관성이 있는가?"
4. QA: "모든 케이스를 테스트했는가?"
5. User: "실제로 더 나아졌는가?"