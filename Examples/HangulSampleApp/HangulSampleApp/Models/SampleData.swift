import Foundation

enum SampleData {
    static let keywords: [SampleKeyword] = [
        .init(id: 1, title: "프론트엔드", subtitle: "frontend", tags: ["웹", "개발", "UI"]),
        .init(id: 2, title: "백엔드", subtitle: "backend", tags: ["서버", "API", "개발"]),
        .init(id: 3, title: "검색", subtitle: "search", tags: ["추천", "랭킹", "인덱스"]),
        .init(id: 4, title: "결제", subtitle: "payment", tags: ["커머스", "정산", "checkout"]),
        .init(id: 5, title: "네이버", subtitle: "naver", tags: ["포털", "검색엔진"]),
        .init(id: 6, title: "카카오", subtitle: "kakao", tags: ["메신저", "플랫폼"]),
        .init(id: 7, title: "회원가입", subtitle: "sign up", tags: ["인증", "계정"]),
        .init(id: 8, title: "로그인", subtitle: "log in", tags: ["인증", "보안"]),
        .init(id: 9, title: "비밀번호", subtitle: "password", tags: ["보안", "인증"]),
        .init(id: 10, title: "데이터베이스", subtitle: "database", tags: ["저장소", "인프라"]),
        .init(id: 11, title: "클라우드", subtitle: "cloud", tags: ["인프라", "배포"]),
        .init(id: 12, title: "알림", subtitle: "notification", tags: ["푸시", "실시간"]),
        .init(id: 13, title: "장바구니", subtitle: "cart", tags: ["커머스", "주문"]),
        .init(id: 14, title: "주문내역", subtitle: "order history", tags: ["커머스", "주문", "결제"]),
        .init(id: 15, title: "환불", subtitle: "refund", tags: ["결제", "고객지원"]),
        .init(id: 16, title: "프로필", subtitle: "profile", tags: ["계정", "설정"]),
        .init(id: 17, title: "설정", subtitle: "settings", tags: ["환경", "앱"]),
        .init(id: 18, title: "고객센터", subtitle: "support", tags: ["고객지원", "문의"]),
        .init(id: 19, title: "추천", subtitle: "recommendation", tags: ["검색", "개인화"]),
        .init(id: 20, title: "실시간검색", subtitle: "realtime search", tags: ["검색", "트렌드"]),
        .init(id: 21, title: "지도", subtitle: "map", tags: ["위치", "탐색"]),
        .init(id: 22, title: "배송조회", subtitle: "tracking", tags: ["물류", "배송", "주문"]),
        .init(id: 23, title: "정기결제", subtitle: "subscription", tags: ["결제", "멤버십"]),
        .init(id: 24, title: "광고관리", subtitle: "ads", tags: ["마케팅", "비즈니스"]),
        .init(id: 25, title: "통계", subtitle: "analytics", tags: ["대시보드", "지표"]),
        .init(id: 26, title: "할인쿠폰", subtitle: "coupon", tags: ["프로모션", "커머스"]),
        .init(id: 27, title: "상품상세", subtitle: "product detail", tags: ["커머스", "탐색"]),
        .init(id: 28, title: "재고관리", subtitle: "inventory", tags: ["물류", "운영"]),
        .init(id: 29, title: "검색자동완성", subtitle: "autocomplete", tags: ["검색", "자동완성", "UX"]),
        .init(id: 30, title: "검색어교정", subtitle: "spell correction", tags: ["오타", "교정", "유사검색"]),
        .init(id: 31, title: "프롬프트", subtitle: "prompt", tags: ["AI", "LLM"]),
        .init(id: 32, title: "모니터링", subtitle: "monitoring", tags: ["관측성", "운영"]),
        .init(id: 33, title: "에러리포트", subtitle: "error report", tags: ["품질", "로그"]),
        .init(id: 34, title: "권한관리", subtitle: "authorization", tags: ["보안", "정책"]),
        .init(id: 35, title: "초성검색", subtitle: "choseong search", tags: ["한글", "검색"]),
        .init(id: 36, title: "형태소분석", subtitle: "morphological analysis", tags: ["한국어", "NLP"]),
        .init(id: 37, title: "네트워크", subtitle: "network", tags: ["통신", "인프라"]),
        .init(id: 38, title: "배치작업", subtitle: "batch", tags: ["스케줄", "처리"]),
        .init(id: 39, title: "프론트", subtitle: "front", tags: ["vmfhsxm", "키보드오타"]),
        .init(id: 40, title: "검색엔진", subtitle: "search engine", tags: ["인덱스", "랭킹"]),
    ]

    static let coreTextExamples: [String] = [
        "값",
        "한글 검색",
        "프론트엔드",
        "데이터베이스",
        "안녕하세요"
    ]

    static let qwertyExamples: [String] = [
        "vmfhsxmdpsem",
        "spdlqj",
        "rkatn",
        "dkssudgktpdy"
    ]

    static let numberExamples: [String] = [
        "1234",
        "20000000",
        "100000001",
        "319.04"
    ]
}
