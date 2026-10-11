import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../app/l10n.dart';
import '../models/product.dart';
import '../models/review.dart';
import 'auth_service.dart';

class ProductService extends ChangeNotifier {
  final AuthService auth;

  List<Product> _products = [];
  bool _loading = false;
  String _currentCategory = 'all';
  String _searchQuery = '';

  // Cached "my page" lists — kept here so all screens that watch the service
  // stay in sync (like/unlike, upload, status change, delete all reflect instantly).
  List<Product> _myLikes = [];
  bool _myLikesLoading = false;
  bool _myLikesLoaded = false;

  List<Product> _mySelling = [];
  bool _mySellingLoading = false;
  bool _mySellingLoaded = false;

  ProductService(this.auth);

  List<Product> get products => _products;
  bool get loading => _loading;

  /// 마지막 피드 로드 실패 문구 (성공하면 null). 실패를 "상품 없음" 과 구분해서 보여준다.
  String? _loadError;
  String? get loadError => _loadError;
  String get currentCategory => _currentCategory;

  List<Product> get myLikes => _myLikes;
  bool get myLikesLoading => _myLikesLoading;
  bool get myLikesLoaded => _myLikesLoaded;

  List<Product> get mySelling => _mySelling;
  bool get mySellingLoading => _mySellingLoading;
  bool get mySellingLoaded => _mySellingLoaded;

  /// 거리 필터 (당근식 동네 범위 슬라이더). 0 = 비활성, 2/4/6/10 km.
  /// 동네 인증 안 된 사용자가 지정하면 서버에서 무시된다.
  int _rangeKm = 0;
  int get rangeKm => _rangeKm;
  set rangeKm(int v) {
    if (_rangeKm == v) return;
    _rangeKm = v;
    notifyListeners();
  }

  Future<void> fetchProducts({
    String category = 'all',
    String? region,
    String? search,
    int? rangeKm,
  }) async {
    _loading = true;
    _currentCategory = category;
    _searchQuery = search ?? '';
    if (rangeKm != null) _rangeKm = rangeKm;
    notifyListeners();

    try {
      final res = await auth.api.get('/api/products', query: {
        if (category != 'all') 'category': category,
        // 거리 필터가 켜져 있으면 region 단순 필터는 끈다 (반경이 더 정확함).
        if (_rangeKm == 0 && region != null && region.isNotEmpty)
          'region': region,
        if (search != null && search.isNotEmpty) 'search': search,
        if (_rangeKm > 0) 'range_km': '$_rangeKm',
      });
      final list = (res.data['products'] as List? ?? [])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      _products = list;
      _loadError = null;
    } catch (e) {
      debugPrint('fetchProducts error: $e');
      _products = [];
      _loadError = _serverError(e) ?? L10n.current.productLoadFailed;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// [peek] — 조회수·둘러보기 채굴 없이 읽기만 (채팅방 배너 등 보조 조회용).
  Future<Product?> fetchById(String id, {bool peek = false}) async {
    try {
      final res = await auth.api.get(
        '/api/products/$id',
        query: peek ? const {'peek': '1'} : null,
      );
      final data = res.data as Map<String, dynamic>;
      // 응답에 mining 필드(둘러보기 채굴 진행도)가 있으면 콜백으로 넘긴다.
      final mining = data['mining'];
      if (mining is Map && _onMiningUpdate != null) {
        _onMiningUpdate!(Map<String, dynamic>.from(mining));
      }
      return Product.fromJson(data['product'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('fetchById error: $e');
      return null;
    }
  }

  /// 상품 상세 응답의 mining 필드 수신 콜백 (QtaService 가 등록).
  void Function(Map<String, dynamic>)? _onMiningUpdate;
  void setMiningUpdateCallback(void Function(Map<String, dynamic>)? cb) {
    _onMiningUpdate = cb;
  }

  /// 마지막 상품 등록으로 채굴된 QTA (등록 가격의 10%, 1 QTA = 10원).
  int lastListingReward = 0;

  /// 마지막 상품 삭제로 차감된 등록 채굴 QTA.
  int lastListingClawback = 0;

  Future<String?> createProduct({
    required String title,
    required String description,
    required int price,
    int qtaPrice = 0,
    required String category,
    required String region,
    required List<File> imageFiles,
    String youtubeUrl = '',
    File? videoFile,
  }) async {
    try {
      final fields = <String, dynamic>{
        'title': title,
        'description': description,
        'price': price,
        'qta_price': qtaPrice,
        'category': category,
        'region': region,
      };
      if (youtubeUrl.trim().isNotEmpty) {
        fields['youtube_url'] = youtubeUrl.trim();
      }

      final form = FormData.fromMap(fields);
      for (var i = 0; i < imageFiles.length; i++) {
        form.files.add(MapEntry(
          'images',
          await MultipartFile.fromFile(
            imageFiles[i].path,
            filename: 'image_$i.jpg',
          ),
        ));
      }
      // Only send uploaded video if YouTube URL not provided (server ignores otherwise)
      if (youtubeUrl.trim().isEmpty && videoFile != null) {
        final name = videoFile.path.split('/').last;
        form.files.add(MapEntry(
          'video',
          await MultipartFile.fromFile(videoFile.path, filename: name),
        ));
      }

      final res = await auth.api.dio.post(
        '/api/products',
        data: form,
        options: Options(
          // Uploading video can take a while on slow networks
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        lastListingReward = (res.data is Map)
            ? ((res.data['listing_reward'] as num?)?.toInt() ?? 0)
            : 0;
        // Refresh caches so new product shows up on the feed and on
        // "내가 판매중인 상품" immediately.
        // Fire-and-forget; UI has already navigated away.
        fetchProducts(
          category: _currentCategory,
          region: region,
          search: _searchQuery.isEmpty ? null : _searchQuery,
        );
        fetchMyProducts(silent: true);
        return null; // success
      }
      return res.data?['error']?.toString() ?? L10n.current.productCreateFailed;
    } catch (e) {
      debugPrint('createProduct error: $e');
      return _serverError(e) ?? L10n.current.productCreateFailedRetry;
    }
  }

  Future<bool> toggleLike(String productId) async {
    try {
      final res = await auth.api.post('/api/products/$productId/like');

      // Determine new like state from the feed copy if present; otherwise from
      // the myLikes cache.
      bool? prevLiked;
      Product? base;
      final feedIdx = _products.indexWhere((p) => p.id == productId);
      if (feedIdx != -1) {
        prevLiked = _products[feedIdx].isLiked;
        base = _products[feedIdx];
      } else {
        final likeIdx = _myLikes.indexWhere((p) => p.id == productId);
        if (likeIdx != -1) {
          prevLiked = _myLikes[likeIdx].isLiked;
          base = _myLikes[likeIdx];
        }
      }

      if (base != null && prevLiked != null) {
        final newLiked = !prevLiked;
        final updated = _withLiked(base, newLiked);
        if (feedIdx != -1) _products[feedIdx] = updated;

        // Keep the "찜" tab in sync with no extra round trip.
        final likeIdx = _myLikes.indexWhere((p) => p.id == productId);
        if (newLiked) {
          if (likeIdx == -1) {
            _myLikes.insert(0, updated);
          } else {
            _myLikes[likeIdx] = updated;
          }
        } else {
          if (likeIdx != -1) _myLikes.removeAt(likeIdx);
        }
        notifyListeners();
      }
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('toggleLike error: $e');
      return false;
    }
  }

  /// ★ 7차 푸시 (이슈 1): 찜 탭 마지막 에러 메시지 — 빈 목록과 에러를 분기하기 위함.
  /// null 이면 "에러 없음 (정상 빈 목록)", 비어있지 않으면 에러 화면 + 재시도 버튼 노출.
  String? _myLikesError;
  String? get myLikesError => _myLikesError;

  /// Reload the user's liked products into the cache.
  /// Returns the list for convenience.
  ///
  /// ★ v1.0.115 (사장님 보고 — 찜한 상품 보였다가 안 보였다가 깜빡임 수정):
  ///   - 동시 호출 차단: 이미 로딩 중이면 즉시 캐시 반환 (중복 fetch 방지).
  ///   - silent=true 일 땐 fetch 시작 시 notifyListeners() 호출 안 함
  ///     → build 도중 fetch 가 발사돼도 ListView 가 다시 그려지지 않음.
  ///   - 응답 동일하면 list 자체를 교체하지 않아 ListView 재구성 0건.
  Future<List<Product>> fetchMyLikes({bool silent = false}) async {
    // ★ 동시 호출 차단 — build 마다 호출돼도 단일 진입만 허용.
    if (_myLikesLoading) return _myLikes;

    _myLikesLoading = true;
    if (!silent) {
      _myLikesError = null;
      notifyListeners();
    }
    bool dataChanged = false;
    bool errorChanged = false;
    try {
      final res = await auth.api.get('/api/products/my/likes');
      final fetched = (res.data['products'] as List? ?? [])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();

      // ★ 동일 결과면 list 교체 생략 — ListView 가 재구성되지 않아 깜빡임 0.
      if (!_isSameProductList(_myLikes, fetched)) {
        _myLikes = fetched;
        dataChanged = true;
      }
      if (!_myLikesLoaded) {
        _myLikesLoaded = true;
        dataChanged = true;
      }
      if (_myLikesError != null) {
        _myLikesError = null;
        errorChanged = true;
      }
    } catch (e) {
      debugPrint('fetchMyLikes error: $e');
      // ★ 이슈 1: 에러 시에도 _myLikesLoaded=true 로 set 해야 다음 진입 때
      //  silent=true 로 가서 무한 빈화면 루프 방지. _myLikesError 로 에러 노출.
      if (!_myLikesLoaded) {
        _myLikesLoaded = true;
        dataChanged = true;
      }
      final newErr = L10n.current.productLikesLoadFailed;
      if (_myLikesError != newErr) {
        _myLikesError = newErr;
        errorChanged = true;
      }
      // _myLikes 는 기존 캐시 유지 (네트워크 일시 오류 시 화면 깜빡임 방지).
    } finally {
      _myLikesLoading = false;
      // ★ v1.0.115 (사장님 보고 — 깜빡임 수정):
      //   silent=true 일 때는 데이터가 실제로 바뀐 경우에만 notify.
      //   동일 응답 반복 시 ListView 가 절대 재구성되지 않음 → 깜빡임 0건.
      //   non-silent 일 땐 로딩 표시 해제를 위해 항상 notify.
      if (!silent || dataChanged || errorChanged) {
        notifyListeners();
      }
    }
    return _myLikes;
  }

  /// 두 상품 list 가 동일한지 (id + isLiked + status 비교).
  bool _isSameProductList(List<Product> a, List<Product> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].isLiked != b[i].isLiked ||
          a[i].status != b[i].status) {
        return false;
      }
    }
    return true;
  }

  /// Reload the user's own uploaded products into the cache.
  Future<List<Product>> fetchMyProducts({bool silent = false}) async {
    if (!silent) {
      _mySellingLoading = true;
      notifyListeners();
    }
    try {
      final res = await auth.api.get('/api/products/my/selling');
      _mySelling = (res.data['products'] as List? ?? [])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      _mySellingLoaded = true;
    } catch (e) {
      debugPrint('fetchMyProducts error: $e');
      _mySelling = [];
    } finally {
      _mySellingLoading = false;
      notifyListeners();
    }
    return _mySelling;
  }

  /// Edit an existing product. Only the owner can call this (server enforces).
  /// Any field left null is left untouched on the server.
  /// Returns null on success, error string on failure.
  Future<String?> updateProduct(
    String productId, {
    String? title,
    String? description,
    int? price,
    int? qtaPrice,
    String? category,
    String? region,
    String? youtubeUrl,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (description != null) data['description'] = description;
      if (price != null) data['price'] = price;
      if (qtaPrice != null) data['qta_price'] = qtaPrice;
      if (category != null) data['category'] = category;
      if (region != null) data['region'] = region;
      // Empty string means "clear YouTube URL" (server understands this).
      if (youtubeUrl != null) data['youtube_url'] = youtubeUrl;

      if (data.isEmpty) return L10n.current.productNothingToUpdate;

      final res = await auth.api.dio.patch(
        '/api/products/$productId',
        data: data,
      );
      if (res.statusCode == 200) {
        // Replace the updated product in every local cache.
        final map = (res.data is Map) ? res.data['product'] : null;
        if (map is Map<String, dynamic>) {
          final updated = Product.fromJson(map);
          final fIdx = _products.indexWhere((p) => p.id == productId);
          if (fIdx >= 0) _products[fIdx] = updated;
          final sIdx = _mySelling.indexWhere((p) => p.id == productId);
          if (sIdx >= 0) _mySelling[sIdx] = updated;
          final lIdx = _myLikes.indexWhere((p) => p.id == productId);
          if (lIdx >= 0) _myLikes[lIdx] = updated;
          notifyListeners();
        }
        return null;
      }
      return (res.data is Map)
          ? (res.data['error']?.toString() ?? L10n.current.productUpdateFailed)
          : L10n.current.productUpdateFailed;
    } on DioException catch (e) {
      debugPrint('updateProduct error: ${e.response?.data ?? e.message}');
      return (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? L10n.current.productUpdateFailed)
          : L10n.current.productUpdateFailed;
    } catch (e) {
      debugPrint('updateProduct error: $e');
      return L10n.current.productUpdateFailed;
    }
  }

  /// 끌어올리기 — bump the product to the top of the feed.
  /// Returns null on success, an error string (Korean, server-friendly) on failure.
  /// 429 cooldown is surfaced as the server's `error` message.
  Future<String?> bumpProduct(String productId) async {
    try {
      final res = await auth.api.dio.post('/api/products/$productId/bump');
      if (res.statusCode == 200) {
        final map = (res.data is Map) ? res.data['product'] : null;
        if (map is Map<String, dynamic>) {
          final updated = Product.fromJson(map);
          // Refresh in every cache + re-sort the main feed by effectiveAt.
          final fIdx = _products.indexWhere((p) => p.id == productId);
          if (fIdx >= 0) _products[fIdx] = updated;
          _products.sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));

          final sIdx = _mySelling.indexWhere((p) => p.id == productId);
          if (sIdx >= 0) _mySelling[sIdx] = updated;
          _mySelling.sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));

          notifyListeners();
        }
        return null;
      }
      return (res.data is Map)
          ? (res.data['error']?.toString() ?? L10n.current.productBumpFailed)
          : L10n.current.productBumpFailed;
    } on DioException catch (e) {
      debugPrint('bumpProduct error: ${e.response?.data ?? e.message}');
      // 429 cooldown returns a friendly Korean message we should pass through.
      return (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? L10n.current.productBumpFailed)
          : L10n.current.productBumpFailed;
    } catch (e) {
      debugPrint('bumpProduct error: $e');
      return L10n.current.productBumpFailed;
    }
  }

  /// Change product status: 'sale' | 'reserved' | 'sold'.
  /// Returns null on success, error string on failure.
  ///
  /// When [status] == 'sold' and a [buyerId] is provided, the server records
  /// who the listing was sold to so both sides can leave 거래후기 later.
  Future<String?> updateStatus(
    String productId,
    String status, {
    String? buyerId,
  }) async {
    try {
      final res = await auth.api.put(
        '/api/products/$productId/status',
        data: {
          'status': status,
          if (status == 'sold' && buyerId != null) 'buyer_id': buyerId,
        },
      );
      if (res.statusCode == 200) {
        // Update local caches so every tab reflects the new status immediately.
        final feedIdx = _products.indexWhere((p) => p.id == productId);
        if (feedIdx >= 0) {
          _products[feedIdx] = _withStatus(_products[feedIdx], status);
        }
        final sellIdx = _mySelling.indexWhere((p) => p.id == productId);
        if (sellIdx >= 0) {
          _mySelling[sellIdx] = _withStatus(_mySelling[sellIdx], status);
        }
        final likeIdx = _myLikes.indexWhere((p) => p.id == productId);
        if (likeIdx >= 0) {
          _myLikes[likeIdx] = _withStatus(_myLikes[likeIdx], status);
        }
        notifyListeners();
        return null;
      }
      return (res.data is Map) ? (res.data['error']?.toString() ?? L10n.current.productChangeFailed) : L10n.current.productChangeFailed;
    } on DioException catch (e) {
      debugPrint('updateStatus error: ${e.response?.data ?? e.message}');
      return (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? L10n.current.productChangeFailed)
          : L10n.current.productChangeFailed;
    } catch (e) {
      debugPrint('updateStatus error: $e');
      return L10n.current.productChangeFailed;
    }
  }

  /// Permanently delete a product (+ its R2 images).
  Future<String?> deleteProduct(String productId) async {
    try {
      final res = await auth.api.delete('/api/products/$productId');
      if (res.statusCode == 200) {
        lastListingClawback = (res.data is Map)
            ? ((res.data['listing_reward_clawback'] as num?)?.toInt() ?? 0)
            : 0;
        _products.removeWhere((p) => p.id == productId);
        _mySelling.removeWhere((p) => p.id == productId);
        _myLikes.removeWhere((p) => p.id == productId);
        notifyListeners();
        return null;
      }
      return (res.data is Map) ? (res.data['error']?.toString() ?? L10n.current.productDeleteFailed) : L10n.current.productDeleteFailed;
    } on DioException catch (e) {
      debugPrint('deleteProduct error: ${e.response?.data ?? e.message}');
      return (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? L10n.current.productDeleteFailed)
          : L10n.current.productDeleteFailed;
    } catch (e) {
      debugPrint('deleteProduct error: $e');
      return L10n.current.productDeleteFailed;
    }
  }

  /// 판매자가 거래완료로 지정한 구매자 본인이 거래를 확인한다.
  /// 서버가 이때 QTA 결제(qta_price > 0)와 거래 보너스를 실행한다.
  /// Returns null on success, error string on failure.
  Future<String?> confirmPurchase(String productId, {int? expectedQtaPrice}) async {
    try {
      // 화면에서 본 QTA 가격을 함께 보낸다 — 판매자가 그사이 바꿨으면 서버가 거부.
      final res = await auth.api.post(
        '/api/products/$productId/confirm-purchase',
        data: {if (expectedQtaPrice != null) 'expected_qta_price': expectedQtaPrice},
      );
      if (res.statusCode == 200) return null;
      return (res.data is Map) ? (res.data['error']?.toString() ?? L10n.current.productConfirmFailed) : L10n.current.productConfirmFailed;
    } on DioException catch (e) {
      debugPrint('confirmPurchase error: ${e.response?.data ?? e.message}');
      return (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? L10n.current.productConfirmFailed)
          : L10n.current.productConfirmFailed;
    } catch (e) {
      debugPrint('confirmPurchase error: $e');
      return L10n.current.productConfirmFailed;
    }
  }

  Product _withStatus(Product p, String status) {
    return Product(
      id: p.id,
      title: p.title,
      description: p.description,
      price: p.price,
      category: p.category,
      region: p.region,
      market: p.market,
      images: p.images,
      videoUrl: p.videoUrl,
      sellerId: p.sellerId,
      sellerNickname: p.sellerNickname,
      sellerMannerScore: p.sellerMannerScore,
      status: status,
      viewCount: p.viewCount,
      likeCount: p.likeCount,
      chatCount: p.chatCount,
      isLiked: p.isLiked,
      createdAt: p.createdAt,
      // 나머지 필드도 그대로 복사 — 빠뜨리면 목록 캐시에서 QTA 가격·구매자·확인 시각이 사라진다.
      qtaPrice: p.qtaPrice,
      sellerWalletAddress: p.sellerWalletAddress,
      bumpedAt: p.bumpedAt,
      buyerId: p.buyerId,
      buyerConfirmedAt: p.buyerConfirmedAt,
      buyerNickname: p.buyerNickname,
      myReviewRating: p.myReviewRating,
    );
  }

  Product _withLiked(Product p, bool liked) {
    return Product(
      id: p.id,
      title: p.title,
      description: p.description,
      price: p.price,
      category: p.category,
      region: p.region,
      market: p.market,
      images: p.images,
      videoUrl: p.videoUrl,
      sellerId: p.sellerId,
      sellerNickname: p.sellerNickname,
      sellerMannerScore: p.sellerMannerScore,
      status: p.status,
      viewCount: p.viewCount,
      likeCount: liked
          ? p.likeCount + 1
          : (p.likeCount - 1).clamp(0, 999999),
      chatCount: p.chatCount,
      isLiked: liked,
      createdAt: p.createdAt,
      // 나머지 필드도 그대로 복사 — 빠뜨리면 목록 캐시에서 QTA 가격·구매자·확인 시각이 사라진다.
      qtaPrice: p.qtaPrice,
      sellerWalletAddress: p.sellerWalletAddress,
      bumpedAt: p.bumpedAt,
      buyerId: p.buyerId,
      buyerConfirmedAt: p.buyerConfirmedAt,
      buyerNickname: p.buyerNickname,
      myReviewRating: p.myReviewRating,
    );
  }

  /// Drop all cached data (used on logout).
  void clearCaches() {
    _products = [];
    _loadError = null;
    _myLikes = [];
    _myLikesLoaded = false;
    _mySelling = [];
    _mySellingLoaded = false;
    notifyListeners();
  }

  // ─── Reviews / 거래후기 ──────────────────────────────────────────────

  /// 거래완료 시 구매자 지정용 닉네임 검색 (GET /api/users/search).
  ///
  /// 예전에는 `GET /api/products/:id/buyers`(이 상품으로 대화한 사람 목록)를
  /// 불렀는데, 휘발성 채팅 정책으로 서버에서 그 엔드포인트가 삭제돼 항상 404 →
  /// "구매자와 채팅한 기록이 없어요" 만 뜨고 거래완료가 불가능했다.
  /// 이제 화면이 (1) 이 기기의 채팅방 중 이 상품 대화 상대 + (2) 닉네임 검색을
  /// 함께 보여준다. Returns `[ {id, nickname, manner_score} ]`, 실패 시 빈 목록.
  Future<List<Map<String, dynamic>>> searchUsersByNickname(String nickname) async {
    final q = nickname.trim();
    if (q.isEmpty) return [];
    try {
      final res = await auth.api.get('/api/users/search', query: {'nickname': q});
      final list = (res.data?['users'] as List?) ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on DioException catch (e) {
      debugPrint('searchUsersByNickname error: ${e.response?.data ?? e.message}');
      return [];
    } catch (e) {
      debugPrint('searchUsersByNickname error: $e');
      return [];
    }
  }

  /// Submit a review for a 'sold' product (당근식 3단계 — v2).
  ///   [rating]   : 'best' | 'good' | 'bad'
  ///   [tags]     : 매너 항목 코드 ('kind', 'late' …), 최소 1개. 서버가 역할별로 검사.
  ///   [comment]  : optional free-form text (≤ 300 chars on server).
  ///
  /// Returns null on success, Korean error string on failure.
  Future<String?> postReview(
    String productId, {
    required String rating,
    List<String> tags = const [],
    String comment = '',
  }) async {
    try {
      final res = await auth.api.post(
        '/api/products/$productId/review',
        data: {
          'v': 2,
          'rating': rating,
          'tags': tags,
          'comment': comment,
        },
      );
      return res.statusCode == 200
          ? null
          : (res.data is Map
              ? (res.data['error']?.toString() ?? L10n.current.productReviewFailed)
              : L10n.current.productReviewFailed);
    } on DioException catch (e) {
      debugPrint('postReview error: ${e.response?.data ?? e.message}');
      return (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? L10n.current.productReviewFailed)
          : L10n.current.productReviewFailed;
    } catch (e) {
      debugPrint('postReview error: $e');
      return L10n.current.productReviewFailed;
    }
  }

  /// Returns the current user's review on this product, or null if none yet.
  Future<Review?> fetchMyReview(String productId) async {
    try {
      final res = await auth.api.get('/api/products/$productId/review/me');
      final raw = res.data?['review'];
      if (raw == null) return null;
      return Review.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      debugPrint('fetchMyReview error: $e');
      return null;
    }
  }

  /// 구매 내역 — 판매자가 나를 구매자로 지정한 거래완료 상품 (GET /api/products/my/purchases).
  /// 각 상품의 [Product.myReviewRating] 으로 후기 보냈는지 안다. 실패하면 null.
  Future<List<Product>?> fetchMyPurchases() async {
    try {
      final res = await auth.api.get('/api/products/my/purchases');
      final list = (res.data?['products'] as List?) ?? [];
      return list
          .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('fetchMyPurchases error: $e');
      return null;
    }
  }

  /// Public profile of a user (nickname, region, manner_score, stats).
  Future<Map<String, dynamic>?> fetchUserProfile(String userId) async {
    try {
      final res = await auth.api.get('/api/users/$userId/profile');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      debugPrint('fetchUserProfile error: $e');
      return null;
    }
  }

  /// Reviews received by a user (newest first). 'bad' 평가는 서버가 빼고 준다.
  /// [withComment] 면 후기 글이 있는 것만 ("받은 거래 후기").
  Future<List<Review>> fetchUserReviews(String userId,
      {int limit = 20, DateTime? before, bool withComment = false}) async {
    try {
      final res = await auth.api.get(
        '/api/users/$userId/reviews',
        query: {
          'limit': limit,
          if (before != null) 'before': _serverTime(before),
          if (withComment) 'with_comment': '1',
        },
      );
      final list = (res.data?['reviews'] as List?) ?? [];
      return list
          .map((e) => Review.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('fetchUserReviews error: $e');
      return [];
    }
  }
}

/// 서버 created_at 형식('YYYY-MM-DD HH:MM:SS', UTC)으로 — 페이지 커서 비교가 문자열 비교라서
/// ISO 'T' 형식을 보내면 같은 날짜의 행이 잘못 걸러진다.
String _serverTime(DateTime t) {
  final s = t.toIso8601String().replaceFirst('T', ' ');
  return s.length >= 19 ? s.substring(0, 19) : s;
}

/// DioException 에서 서버가 준 한국어 오류 문구를 꺼낸다 (없으면 null).
/// 사용자 화면에 "DioException [bad response]..." 같은 원문이 보이지 않게 한다.
String? _serverError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return L10n.current.productNetworkSlow;
    }
    if (e.type == DioExceptionType.connectionError) {
      return L10n.current.productNetworkUnreachable;
    }
  }
  return null;
}
