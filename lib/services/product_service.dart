import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/product.dart';
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
  String get currentCategory => _currentCategory;

  List<Product> get myLikes => _myLikes;
  bool get myLikesLoading => _myLikesLoading;
  bool get myLikesLoaded => _myLikesLoaded;

  List<Product> get mySelling => _mySelling;
  bool get mySellingLoading => _mySellingLoading;
  bool get mySellingLoaded => _mySellingLoaded;

  Future<void> fetchProducts({String category = 'all', String? region, String? search}) async {
    _loading = true;
    _currentCategory = category;
    _searchQuery = search ?? '';
    notifyListeners();

    try {
      final res = await auth.api.get('/api/products', query: {
        if (category != 'all') 'category': category,
        if (region != null && region.isNotEmpty) 'region': region,
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final list = (res.data['products'] as List? ?? [])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      _products = list;
    } catch (e) {
      debugPrint('fetchProducts error: $e');
      _products = [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Product?> fetchById(String id) async {
    try {
      final res = await auth.api.get('/api/products/$id');
      return Product.fromJson(res.data['product'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('fetchById error: $e');
      return null;
    }
  }

  Future<String?> createProduct({
    required String title,
    required String description,
    required int price,
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
      return res.data?['error']?.toString() ?? '등록 실패';
    } catch (e) {
      debugPrint('createProduct error: $e');
      return '등록 실패: $e';
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

  /// Reload the user's liked products into the cache.
  /// Returns the list for convenience.
  Future<List<Product>> fetchMyLikes({bool silent = false}) async {
    if (!silent) {
      _myLikesLoading = true;
      notifyListeners();
    }
    try {
      final res = await auth.api.get('/api/products/my/likes');
      _myLikes = (res.data['products'] as List? ?? [])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      _myLikesLoaded = true;
    } catch (e) {
      debugPrint('fetchMyLikes error: $e');
      _myLikes = [];
    } finally {
      _myLikesLoading = false;
      notifyListeners();
    }
    return _myLikes;
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
    String? category,
    String? youtubeUrl,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (description != null) data['description'] = description;
      if (price != null) data['price'] = price;
      if (category != null) data['category'] = category;
      // Empty string means "clear YouTube URL" (server understands this).
      if (youtubeUrl != null) data['youtube_url'] = youtubeUrl;

      if (data.isEmpty) return '수정할 내용이 없어요';

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
          ? (res.data['error']?.toString() ?? '수정 실패')
          : '수정 실패';
    } on DioException catch (e) {
      debugPrint('updateProduct error: ${e.response?.data ?? e.message}');
      return (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? '수정 실패')
          : '수정 실패';
    } catch (e) {
      debugPrint('updateProduct error: $e');
      return '수정 실패';
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
          ? (res.data['error']?.toString() ?? '끌어올리기 실패')
          : '끌어올리기 실패';
    } on DioException catch (e) {
      debugPrint('bumpProduct error: ${e.response?.data ?? e.message}');
      // 429 cooldown returns a friendly Korean message we should pass through.
      return (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? '끌어올리기 실패')
          : '끌어올리기 실패';
    } catch (e) {
      debugPrint('bumpProduct error: $e');
      return '끌어올리기 실패';
    }
  }

  /// Change product status: 'sale' | 'reserved' | 'sold'.
  /// Returns null on success, error string on failure.
  Future<String?> updateStatus(String productId, String status) async {
    try {
      final res = await auth.api.put(
        '/api/products/$productId/status',
        data: {'status': status},
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
      return (res.data is Map) ? (res.data['error']?.toString() ?? '변경 실패') : '변경 실패';
    } on DioException catch (e) {
      debugPrint('updateStatus error: ${e.response?.data ?? e.message}');
      return (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? '변경 실패')
          : '변경 실패';
    } catch (e) {
      debugPrint('updateStatus error: $e');
      return '변경 실패';
    }
  }

  /// Permanently delete a product (+ its R2 images).
  Future<String?> deleteProduct(String productId) async {
    try {
      final res = await auth.api.delete('/api/products/$productId');
      if (res.statusCode == 200) {
        _products.removeWhere((p) => p.id == productId);
        _mySelling.removeWhere((p) => p.id == productId);
        _myLikes.removeWhere((p) => p.id == productId);
        notifyListeners();
        return null;
      }
      return (res.data is Map) ? (res.data['error']?.toString() ?? '삭제 실패') : '삭제 실패';
    } on DioException catch (e) {
      debugPrint('deleteProduct error: ${e.response?.data ?? e.message}');
      return (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? '삭제 실패')
          : '삭제 실패';
    } catch (e) {
      debugPrint('deleteProduct error: $e');
      return '삭제 실패';
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
    );
  }

  /// Drop all cached data (used on logout).
  void clearCaches() {
    _products = [];
    _myLikes = [];
    _myLikesLoaded = false;
    _mySelling = [];
    _mySellingLoaded = false;
    notifyListeners();
  }
}
