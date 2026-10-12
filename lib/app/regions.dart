import 'regions_jp.dart';
import 'regions_ph.dart';

/// 동네(지역) 목록. 이름은 서버 workers-server/src/regions.ts 와 같아야 한다
/// (동네 인증 좌표·시장 구분을 이 이름으로 찾는다).
class AppRegions {
  static const List<String> kr = [
    '서울 강남구', '서울 강동구', '서울 강북구', '서울 강서구',
    '서울 관악구', '서울 광진구', '서울 구로구', '서울 금천구',
    '서울 노원구', '서울 도봉구', '서울 동대문구', '서울 동작구',
    '서울 마포구', '서울 서대문구', '서울 서초구', '서울 성동구',
    '서울 성북구', '서울 송파구', '서울 양천구', '서울 영등포구',
    '서울 용산구', '서울 은평구', '서울 종로구', '서울 중구', '서울 중랑구',
    '경기 수원시', '경기 성남시', '경기 용인시', '경기 고양시',
    '경기 부천시', '경기 안산시', '경기 안양시', '경기 남양주시',
    '경기 화성시', '경기 평택시', '경기 의정부시', '경기 시흥시',
    '경기 파주시', '경기 광명시', '경기 김포시', '경기 광주시',
    '인천 중구', '인천 동구', '인천 미추홀구', '인천 연수구',
    '인천 남동구', '인천 부평구', '인천 계양구', '인천 서구',
    '부산 해운대구', '부산 수영구', '부산 남구', '부산 연제구',
    '대구 중구', '대구 동구', '대구 서구', '대구 남구', '대구 북구',
    '대전 서구', '대전 유성구', '대전 중구',
    '광주 북구', '광주 남구', '광주 서구', '광주 동구',
    '울산 남구', '울산 중구', '울산 동구',
    '세종 세종시',
    '제주 제주시', '제주 서귀포시',
  ];

  /// 일본: 47 都道府県의 모든 市区町村 ('<都道府県> <市区町村>', 政令市는 行政区까지).
  /// 데이터는 regions_jp.dart (tool/gen_jp_regions.mjs 로 생성).
  static final List<String> jp = [
    for (final e in JpRegionData.byPrefecture.entries)
      for (final c in e.value) '${e.key} ${c.$1}',
  ];

  /// 일본 都道府県 (JIS 코드 순).
  static List<String> get jpPrefectures =>
      JpRegionData.byPrefecture.keys.toList(growable: false);

  /// 그 都道府県의 市区町村 — (전체 이름, 짧은 이름, 읽기 가타카나).
  static List<(String, String, String)> jpCities(String prefecture) => [
        for (final c in JpRegionData.byPrefecture[prefecture] ?? const <(String, String)>[])
          ('$prefecture ${c.$1}', c.$1, c.$2),
      ];

  /// 일본 지역 이름에서 都道府県 ('大阪府 大阪市北区' → '大阪府'). 일본 지역이 아니면 null.
  static String? jpPrefectureOf(String region) {
    final i = region.indexOf(' ');
    if (i <= 0) return null;
    final p = region.substring(0, i);
    return JpRegionData.byPrefecture.containsKey(p) ? p : null;
  }

  /// 필리핀: 모든 Province 의 City/Municipality ('<Province> · <City/Municipality>').
  /// NCR 은 'Metro Manila'. 데이터는 regions_ph.dart (tool/gen_ph_regions.mjs 로 생성).
  static final List<String> ph = [
    for (final e in PhRegionData.byProvince.entries)
      for (final c in e.value) '${e.key}${PhRegionData.sep}$c',
  ];

  /// 필리핀 Province (Metro Manila 먼저, 나머지 알파벳 순).
  static List<String> get phProvinces =>
      PhRegionData.byProvince.keys.toList(growable: false);

  /// 그 Province 의 City/Municipality — (전체 이름, 짧은 이름).
  static List<(String, String)> phCities(String province) => [
        for (final c in PhRegionData.byProvince[province] ?? const <String>[])
          ('$province${PhRegionData.sep}$c', c),
      ];

  /// 필리핀 지역 이름에서 Province ('Cebu · Cebu City' → 'Cebu'). 필리핀 지역이 아니면 null.
  static String? phProvinceOf(String region) {
    final i = region.indexOf(PhRegionData.sep);
    if (i <= 0) return null;
    final p = region.substring(0, i);
    return PhRegionData.byProvince.containsKey(p) ? p : null;
  }

  static List<String> forMarket(String market) => switch (market) {
        'jp' => jp,
        'ph' => ph,
        _ => kr,
      };
}
