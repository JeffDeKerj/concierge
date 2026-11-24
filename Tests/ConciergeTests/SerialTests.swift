import Testing

/// Every suite shares the one throwaway project folder, so they must run one
/// at a time. `.serialized` on this parent applies to the nested suites too.
@Suite(.serialized)
enum SerialTests {}
