import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/l10n/app_locale_codes.dart';
import '../../../../core/services/ai_translation_service.dart';
import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';
import '../../../catalog/domain/models/catalog_constants.dart';
/// Форма добавления товара с AI-переводом и ручной правкой.
class AdminProductForm extends StatefulWidget {
  const AdminProductForm({
    super.key,
    required this.database,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.onSubmit,
  });

  final DatabaseService database;
  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<ProductItem> onSubmit;
  @override
  State<AdminProductForm> createState() => _AdminProductFormState();
}

class _AdminProductFormState extends State<AdminProductForm> {
  final _nameRuController = TextEditingController();
  final _descriptionRuController = TextEditingController();
  final _priceController = TextEditingController();
  final _discountController = TextEditingController();

  final _nameKkController = TextEditingController();
  final _nameKoController = TextEditingController();
  final _nameEnController = TextEditingController();
  final _nameUzController = TextEditingController();
  final _descriptionKkController = TextEditingController();
  final _descriptionKoController = TextEditingController();
  final _descriptionEnController = TextEditingController();
  final _descriptionUzController = TextEditingController();

  bool _isTranslating = false;
  File? _pickedImageFile;
  String? _uploadedImageUrl;
  bool _isUploadingImage = false;

  @override
  void dispose() {
    _nameRuController.dispose();
    _descriptionRuController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _nameKkController.dispose();
    _nameKoController.dispose();
    _nameEnController.dispose();
    _nameUzController.dispose();
    _descriptionKkController.dispose();
    _descriptionKoController.dispose();
    _descriptionEnController.dispose();
    _descriptionUzController.dispose();
    super.dispose();
  }

  Future<void> _translateAll() async {
    final ruName = _nameRuController.text.trim();
    if (ruName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала введите название на русском')),
      );
      return;
    }

    setState(() => _isTranslating = true);
    try {
      final result = await translateProductFromRussian(
        ruName: ruName,
        ruDescription: _descriptionRuController.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _nameKkController.text = result.names[AppLocaleCodes.kk] ?? '';
        _nameKoController.text = result.names[AppLocaleCodes.ko] ?? '';
        _nameEnController.text = result.names[AppLocaleCodes.en] ?? '';
        _nameUzController.text = result.names[AppLocaleCodes.uz] ?? '';
        _descriptionKkController.text =
            result.descriptions[AppLocaleCodes.kk] ?? '';
        _descriptionKoController.text =
            result.descriptions[AppLocaleCodes.ko] ?? '';
        _descriptionEnController.text =
            result.descriptions[AppLocaleCodes.en] ?? '';
        _descriptionUzController.text =
            result.descriptions[AppLocaleCodes.uz] ?? '';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.translationDone),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка перевода: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_isUploadingImage) return;

    final file = await widget.database.pickProductImageFromGallery();
    if (!mounted) return;
    if (file == null) return;

    setState(() {
      _pickedImageFile = file;
      _uploadedImageUrl = null;
      _isUploadingImage = true;
    });

    try {
      final url = await widget.database.uploadProductImageToStorage(file);
      if (!mounted) return;

      if (url == null || url.isEmpty) {
        setState(() {
          _pickedImageFile = null;
          _uploadedImageUrl = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось загрузить фото в облако. Проверьте Supabase и интернет.',
            ),
          ),
        );
        return;
      }

      setState(() => _uploadedImageUrl = url);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pickedImageFile = null;
        _uploadedImageUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки фото: $error')),
      );
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _submit() {
    if (_isUploadingImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Дождитесь окончания загрузки фото')),
      );
      return;
    }
    final ruName = _nameRuController.text.trim();
    final price = int.tryParse(_priceController.text.trim()) ?? 0;
    final discount = int.tryParse(_discountController.text.trim()) ?? 0;

    if (ruName.isEmpty || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните название и цену')),
      );
      return;
    }

    final ruDescription = _descriptionRuController.text.trim();

    final nameMap = {
      AppLocaleCodes.ru: ruName,
      AppLocaleCodes.kk: _nameKkController.text.trim(),
      AppLocaleCodes.ko: _nameKoController.text.trim(),
      AppLocaleCodes.en: _nameEnController.text.trim(),
      AppLocaleCodes.uz: _nameUzController.text.trim(),
    }..removeWhere((_, value) => value.isEmpty);

    final descriptionMap = {
      AppLocaleCodes.ru: ruDescription,
      AppLocaleCodes.kk: _descriptionKkController.text.trim(),
      AppLocaleCodes.ko: _descriptionKoController.text.trim(),
      AppLocaleCodes.en: _descriptionEnController.text.trim(),
      AppLocaleCodes.uz: _descriptionUzController.text.trim(),
    }..removeWhere((_, value) => value.isEmpty);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final item = ProductItem(
      id: 'adm-$stamp',
      sku: 'DJ-ADM-$stamp',
      stockQuantity: 5,
      name: nameMap,
      description: descriptionMap,
      metal: 'Белое золото',
      salePrice: price,
      oldPrice: calculateOldPriceFromDiscount(price, discount),
      discountPercent: discount,
      category: widget.selectedCategory,
      insert: 'Без вставок',
      iconIndex: DateTime.now().millisecondsSinceEpoch % 7,
      imageUrl: _uploadedImageUrl,
    );

    widget.onSubmit(item);
    _clearForm();
  }

  void _clearForm() {
    _nameRuController.clear();
    _descriptionRuController.clear();
    _priceController.clear();
    _discountController.clear();
    _nameKkController.clear();
    _nameKoController.clear();
    _nameEnController.clear();
    _nameUzController.clear();
    _descriptionKkController.clear();
    _descriptionKoController.clear();
    _descriptionEnController.clear();
    _descriptionUzController.clear();
    _pickedImageFile = null;
    _uploadedImageUrl = null;
    _isUploadingImage = false;
  }

  Widget _buildPhotoPreview() {
    if (_pickedImageFile != null && !kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          _pickedImageFile!,
          width: double.infinity,
          height: 160,
          fit: BoxFit.cover,
        ),
      );
    }

    return Container(
      height: 160,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 48,
            color: AppColors.textSecondary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 8),
          Text(
            'Фото не выбрано',
            style: AppTypography.productMeta().copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Text(
          'Добавить товар',
          style: AppTypography.heading(fontSize: 20),
        ),
        const SizedBox(height: 12),
        _AdminFormField(
          controller: _nameRuController,
          label: l10n.productNameRu,
          hint: 'Кольцо с бриллиантом',
        ),
        const SizedBox(height: 12),
        _AdminFormField(
          controller: _descriptionRuController,
          label: l10n.productDescriptionRu,
          hint: 'Изысканное украшение из коллекции Dr. Jewelry',
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isTranslating ? null : _translateAll,
            icon: _isTranslating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded, color: AppColors.accent),
            label: Text(
              _isTranslating ? l10n.translating : l10n.translateAllLanguages,
              style: AppTypography.caption(
                color: AppColors.textOnPrimary,
                fontWeight: FontWeight.w700,
              ).copyWith(fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              disabledBackgroundColor: AppColors.border,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              l10n.translationsTitle,
              style: AppTypography.caption(fontWeight: FontWeight.w600)
                  .copyWith(fontSize: 14),
            ),
            children: [
              _AdminFormField(
                controller: _nameKkController,
                label: '${l10n.languageKk} · Атауы',
                hint: 'Сақина ...',
              ),
              const SizedBox(height: 12),
              _AdminFormField(
                controller: _descriptionKkController,
                label: '${l10n.languageKk} · Сипаттамасы',
                hint: 'Премиум зергерлік бұйым ...',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _AdminFormField(
                controller: _nameKoController,
                label: '${l10n.languageKo} · Название',
                hint: '반지 ...',
              ),
              const SizedBox(height: 12),
              _AdminFormField(
                controller: _descriptionKoController,
                label: '${l10n.languageKo} · Описание',
                hint: '설명 ...',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _AdminFormField(
                controller: _nameEnController,
                label: '${l10n.languageEn} · Name',
                hint: 'Diamond ring ...',
              ),
              const SizedBox(height: 12),
              _AdminFormField(
                controller: _descriptionEnController,
                label: '${l10n.languageEn} · Description',
                hint: 'Premium jewelry ...',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _AdminFormField(
                controller: _nameUzController,
                label: '${l10n.languageUz} · Nomi',
                hint: 'Uzuk ...',
              ),
              const SizedBox(height: 12),
              _AdminFormField(
                controller: _descriptionUzController,
                label: '${l10n.languageUz} · Tavsif',
                hint: 'Premium buyum ...',
                maxLines: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _AdminFormField(
                controller: _priceController,
                label: 'Цена (₩ / KRW)',
                hint: '890000',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AdminFormField(
                controller: _discountController,
                label: 'Скидка, %',
                hint: '60',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Категория', style: AppTypography.productMeta()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in CatalogCategories.items)
              ChoiceChip(
                label: Text(category),
                selected: widget.selectedCategory == category,
                onSelected: (_) => widget.onCategoryChanged(category),
                selectedColor: AppColors.accent.withValues(alpha: 0.2),
                labelStyle: AppTypography.caption(
                  fontWeight: FontWeight.w600,
                ).copyWith(fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Фото товара', style: AppTypography.productMeta()),
        const SizedBox(height: 8),
        Stack(
          alignment: Alignment.center,
          children: [
            _buildPhotoPreview(),
            if (_isUploadingImage)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                ),
              ),
          ],
        ),
        if (_uploadedImageUrl != null) ...[
          const SizedBox(height: 6),
          Text(
            'Загружено в облако',
            style: AppTypography.caption(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ).copyWith(fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isUploadingImage ? null : _pickAndUploadPhoto,
          icon: _isUploadingImage
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _pickedImageFile == null
                      ? Icons.photo_library_outlined
                      : Icons.swap_horiz_rounded,
                ),
          label: Text(
            _pickedImageFile == null
                ? 'Выбрать фото из галереи'
                : 'Изменить фото',
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _isUploadingImage ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Добавить товар'),
          ),
        ),
        ],
      ),
    );
  }
}

class _AdminFormField extends StatelessWidget {
  const _AdminFormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.productMeta()),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.cardBackground,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
