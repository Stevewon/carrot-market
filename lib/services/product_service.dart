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

  ProductService(this.auth);

  List<Product> get products => _products;
  bool get loading => _loading;
  String get currentCategory => _currentCategory;

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
      // Update local state
      final idx = _products.indexWhere((p) => p.id == productId);
      if (idx != -1) {
        final p = _products[idx];
        final newLiked = !p.isLiked;
        _products[idx] = Product(
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
          likeCount: newLiked ? p.likeCount + 1 : (p.likeCount - 1).clamp(0, 999999),
          chatCount: p.chatCount,
          isLiked: newLiked,
          createdAt: p.createdAt,
        );
        notifyListeners();
      }
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('toggleLike error: $e');
      return false;
    }
  }

  Future<List<Product>> fetchMyLikes() async {
    try {
      final res = await auth.api.get('/api/products/my/likes');
      return (res.data['products'] as List? ?? [])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Product>> fetchMyProducts() async {
    try {
      final res = await auth.api.get('/api/products/my/selling');
      return (res.data['products'] as List? ?? [])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }
}
