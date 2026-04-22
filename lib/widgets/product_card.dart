import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app/constants.dart';
import '../app/theme.dart';
import '../models/product.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.images.isNotEmpty
        ? '${AppConfig.apiBase}${product.images.first.startsWith('/') ? '' : '/'}${product.images.first}'
        : null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(
              url: imageUrl,
              status: product.status,
              hasVideo: product.hasVideo,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: EggplantColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${product.region.isEmpty ? "-" : product.region} · ${product.timeAgo}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: EggplantColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (product.status != 'sale')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: product.status == 'reserved'
                                ? EggplantColors.warning
                                : EggplantColors.textSecondary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            product.statusLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Text(
                        product.priceFormatted,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: EggplantColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (product.chatCount > 0) ...[
                        const Icon(Icons.chat_bubble_outline,
                            size: 14, color: EggplantColors.textTertiary),
                        const SizedBox(width: 3),
                        Text('${product.chatCount}',
                            style: const TextStyle(
                                fontSize: 12, color: EggplantColors.textTertiary)),
                        const SizedBox(width: 8),
                      ],
                      if (product.likeCount > 0) ...[
                        Icon(
                          product.isLiked ? Icons.favorite : Icons.favorite_border,
                          size: 14,
                          color: product.isLiked
                              ? EggplantColors.primary
                              : EggplantColors.textTertiary,
                        ),
                        const SizedBox(width: 3),
                        Text('${product.likeCount}',
                            style: const TextStyle(
                                fontSize: 12, color: EggplantColors.textTertiary)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? url;
  final String status;
  final bool hasVideo;

  const _Thumbnail({
    required this.url,
    required this.status,
    this.hasVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 104,
            height: 104,
            color: EggplantColors.background,
            child: url == null
                ? const Center(
                    child: Icon(Icons.image_outlined,
                        size: 36, color: EggplantColors.textTertiary),
                  )
                : CachedNetworkImage(
                    imageUrl: url!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: EggplantColors.background),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: EggplantColors.textTertiary),
                    ),
                  ),
          ),
        ),
        if (status == 'sold')
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  '거래완료',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        if (hasVideo && status != 'sold')
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 14),
                  SizedBox(width: 2),
                  Text('영상',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
