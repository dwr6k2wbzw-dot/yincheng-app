import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'common.dart';

/// 照片小縮圖（Storage receipts/...），點了看大圖；照片已清理時顯示「已超過保存期限」
class PhotoThumb extends StatefulWidget {
  const PhotoThumb({super.key, required this.path, this.size = 48});
  final String path;
  final double size;
  @override
  State<PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<PhotoThumb> {
  Future<String>? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _url ??= AppScope.of(context).repo.shiftPhotoUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    Widget placeholder(IconData icon) => Container(
          width: size,
          height: size,
          color: AppColors.cardHigh,
          child: Icon(icon, color: AppColors.muted, size: 20),
        );
    return Semantics(
      button: true,
      label: '看照片',
      child: GestureDetector(
        onTap: () => showStoragePhoto(context, widget.path),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: FutureBuilder<String>(
            future: _url,
            builder: (context, snap) {
              if (snap.hasError) return placeholder(Icons.image_not_supported_outlined);
              if (!snap.hasData) return placeholder(Icons.image_outlined);
              return Image.network(snap.data!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 3).round(),
                  errorBuilder: (_, __, ___) => placeholder(Icons.image_not_supported_outlined));
            },
          ),
        ),
      ),
    );
  }
}
