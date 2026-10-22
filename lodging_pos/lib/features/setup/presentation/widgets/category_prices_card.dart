import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/buttons.dart';
import '../../../../app/widgets/labeled_field.dart';
import '../../../../app/widgets/money_input.dart';
import '../../../../app/widgets/notes.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/money/kes.dart';
import '../../../price_requests/data/price_requests_repository.dart';
import '../../../price_requests/presentation/price_request_widgets.dart';
import '../../../price_requests/presentation/price_requests_providers.dart';
import '../../../sync/presentation/owner_cloud_prompt.dart';
import '../../data/prices_repository.dart';
import '../../domain/bed_category.dart';
import '../../domain/prices_settings.dart';
import '../prices_providers.dart';
import 'confirm_prices_dialog.dart';

/// "Bed categories" (AD-3): a price per night for each category, saved after
/// a confirmation listing every change; add, close and reopen categories.
/// Read-only without [Permission.editPrices] (the owner's, BR-2); the
/// supervisor gets "Request a change" on each open category instead, or the
/// butter "Waiting" chip while one is with the owner.
class CategoryPricesCard extends ConsumerStatefulWidget {
  const CategoryPricesCard({super.key});

  @override
  ConsumerState<CategoryPricesCard> createState() => _CategoryPricesCardState();
}

class _CategoryPricesCardState extends ConsumerState<CategoryPricesCard> {
  /// Price inputs by category id, and the stored price each one started from.
  final _prices = <String, TextEditingController>{};
  final _stored = <String, int>{};
  var _errors = <String, String>{};

  var _adding = false;
  final _newName = TextEditingController();
  final _newPrice = TextEditingController();
  String? _newNameError;
  String? _newPriceError;

  String? _error;
  String? _saved;
  var _busy = false;

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    _newName.dispose();
    _newPrice.dispose();
    super.dispose();
  }

  /// Keeps one input per category; a stored price that changed (e.g. after
  /// saving) resets its input.
  void _sync(List<CategoryUsage> categories) {
    for (final u in categories) {
      final c = u.category;
      final controller = _prices.putIfAbsent(c.id, TextEditingController.new);
      if (_stored[c.id] != c.pricePerNight) {
        _stored[c.id] = c.pricePerNight;
        controller.text = _plain(c.pricePerNight);
      }
    }
  }

  Map<String, int?> _typed() => {
    for (final MapEntry(:key, :value) in _prices.entries)
      key: parseKes(value.text),
  };

  /// [cloudFirst]: prices, which go to the cloud first under the owner's
  /// sign-in once this desk is connected.
  Future<void> _run(
    Future<void> Function() write, {
    String? done,
    bool cloudFirst = false,
  }) async {
    if (cloudFirst && (!await ensureOwnerCloud(context, ref) || !mounted)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _saved = null;
    });
    try {
      // Prices (and a closed category's request) may go to the cloud first.
      if (!await withOwnerCloud(context, ref, write)) return;
      ref.invalidate(categoryUsageProvider);
      if (mounted) setState(() => _saved = done);
    } on CategoryRuleViolation catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on InvalidPrices catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on NotPermitted {
      if (mounted) {
        setState(() => _error = 'Only the supervisor can change prices.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(List<BedCategory> categories) async {
    final typed = _typed();
    final errors = {
      for (final MapEntry(:key, :value) in typed.entries)
        key: ?priceError(value),
    };
    setState(() {
      _errors = errors;
      _saved = null;
    });
    if (errors.isNotEmpty) return;
    final changes = priceChanges(categories, {
      for (final MapEntry(:key, :value) in typed.entries) key: value!,
    });
    if (changes.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmPricesDialog(changes: changes),
    );
    if (confirmed != true || !mounted) return;
    final user = ref.read(sessionProvider)!;
    await _run(
      () => ref.read(pricesRepositoryProvider).savePrices(user, {
        for (final c in changes) c.categoryId: c.newPrice,
      }),
      done: changes.length == 1 ? 'Price saved.' : 'Prices saved.',
      cloudFirst: true,
    );
  }

  Future<void> _add(List<BedCategory> categories) async {
    final price = parseKes(_newPrice.text);
    setState(() {
      _newNameError = categoryNameError(_newName.text, existing: categories);
      _newPriceError = priceError(price);
    });
    if (_newNameError != null || _newPriceError != null) return;
    final user = ref.read(sessionProvider)!;
    await _run(
      () => ref
          .read(pricesRepositoryProvider)
          .addCategory(user, name: _newName.text, pricePerNight: price!),
      done: 'Category added.',
    );
    if (mounted && _error == null) {
      setState(() => _adding = false);
      _newName.clear();
      _newPrice.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final canEdit = user != null && can(user, Permission.editPrices);
    final canRequest = user != null && can(user, Permission.requestPriceChange);
    final requests = canRequest
        ? ref.watch(supervisorPriceRequestsProvider).value
        : null;
    final usage = ref.watch(categoryUsageProvider);
    final list = usage.value ?? const <CategoryUsage>[];
    _sync(list);
    final categories = [for (final u in list) u.category];
    final typed = _typed();
    final hasChanges = list.any((u) {
      final value = typed[u.category.id];
      return value != u.category.pricePerNight;
    });

    Widget head(String text, {TextAlign align = TextAlign.start}) => Text(
      text,
      textAlign: align,
      style: t.capsLabel.copyWith(color: c.muted),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Bed categories', style: t.sectionTitle),
                  ),
                ),
                if (canEdit && !_adding)
                  TextButton.icon(
                    key: const ValueKey('categories.add'),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _adding = true),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add category'),
                  ),
              ],
            ),
            const SizedBox(height: Space.x16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x12),
              child: Row(
                children: [
                  Expanded(child: head('CATEGORY')),
                  SizedBox(width: _Cols.price, child: head('PRICE PER NIGHT')),
                  if (canEdit) const SizedBox(width: _Cols.was),
                  SizedBox(
                    width: _Cols.beds,
                    child: head('BEDS', align: TextAlign.end),
                  ),
                  SizedBox(width: canEdit ? _Cols.action : _Cols.request),
                ],
              ),
            ),
            const SizedBox(height: Space.x8),
            Divider(height: 1, color: c.line),
            if (usage case AsyncError(:final error))
              Note.error('$error', title: 'Categories could not be loaded.')
            else
              for (final u in list)
                _CategoryRow(
                  usage: u,
                  controller: _prices[u.category.id]!,
                  typed: typed[u.category.id],
                  error: _errors[u.category.id],
                  canEdit: canEdit,
                  canRequest: canRequest,
                  waiting: requests?.waitingFor(u.category.id),
                  busy: _busy,
                  onChanged: () => setState(() => _saved = null),
                  onRequest: () => showRequestPriceDialog(context, u),
                  onClose: () => _run(
                    () => ref
                        .read(pricesRepositoryProvider)
                        .closeCategory(user!, u.category.id),
                  ),
                  onReopen: () => _run(
                    () => ref
                        .read(pricesRepositoryProvider)
                        .reopenCategory(user!, u.category.id),
                  ),
                ),
            if (_adding) ...[
              const SizedBox(height: Space.x16),
              _AddCategoryRow(
                name: _newName,
                price: _newPrice,
                nameError: _newNameError,
                priceError: _newPriceError,
                busy: _busy,
                onAdd: () => _add(categories),
                onCancel: () => setState(() {
                  _adding = false;
                  _newNameError = null;
                  _newPriceError = null;
                }),
              ),
            ],
            const SizedBox(height: Space.x20),
            const Note.info(
              'New prices apply to check-ins after you save. Guests already '
              'staying, and their extensions and refunds, keep the price they '
              'checked in at.',
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.x12),
              Note.error(_error!, key: const ValueKey('prices.error')),
            ],
            const SizedBox(height: Space.x20),
            if (canEdit)
              Wrap(
                spacing: Space.x16,
                runSpacing: Space.x8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppButton.primary(
                    key: const ValueKey('prices.save'),
                    label: 'Save prices',
                    busy: _busy,
                    onPressed: hasChanges ? () => _save(categories) : null,
                  ),
                  if (_saved != null)
                    Text(
                      _saved!,
                      key: const ValueKey('prices.saved'),
                      style: t.small,
                    ),
                ],
              )
            else
              // The supervisor (BR-2): the owner sets prices.
              Text(
                canRequest
                    ? 'Only the owner changes prices. Use “Request a change” '
                          'to ask; the owner approves or rejects it.'
                    : 'Only the owner changes prices.',
                key: const ValueKey('prices.readOnly'),
                style: t.small,
              ),
          ],
        ),
      ),
    );
  }
}

/// `1,000`: the amount without the KES prefix.
String _plain(int kes) => formatKes(kes).substring('KES '.length);

abstract final class _Cols {
  static const price = 160.0;
  static const was = 96.0;
  static const beds = 48.0;
  static const action = 96.0;

  /// The supervisor's "Request a change" or "Waiting" chip, where the
  /// owner's "was" and action columns are.
  static const request = was + action;
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.usage,
    required this.controller,
    required this.typed,
    required this.error,
    required this.canEdit,
    required this.canRequest,
    required this.waiting,
    required this.busy,
    required this.onChanged,
    required this.onRequest,
    required this.onClose,
    required this.onReopen,
  });

  final CategoryUsage usage;
  final TextEditingController controller;
  final int? typed;
  final String? error;
  final bool canEdit;

  /// The supervisor: may ask the owner for a new price.
  final bool canRequest;

  /// This category's request waiting for the owner, if any.
  final PriceRequestView? waiting;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onRequest;
  final VoidCallback onClose;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final category = usage.category;
    final id = category.id;
    final changed = typed != category.pricePerNight;
    final blocker = closeCategoryBlocker(
      category,
      activeBeds: usage.activeBeds,
    );

    final Widget action;
    if (!canEdit) {
      action = switch (waiting) {
        _ when !canRequest || !category.isActive => const SizedBox.shrink(),
        final w? => StatusBadge(
          'WAITING · KES ${_plain(w.request.newPrice)}',
          key: ValueKey('categories.waiting.$id'),
          tone: BadgeTone.warning,
        ),
        null => TextButton(
          key: ValueKey('categories.request.$id'),
          onPressed: onRequest,
          child: const Text('Request a change'),
        ),
      };
    } else if (category.isActive) {
      final button = TextButton(
        key: ValueKey('categories.close.$id'),
        onPressed: blocker != null || busy ? null : onClose,
        style: TextButton.styleFrom(foregroundColor: c.redText),
        child: const Text('Close'),
      );
      action = blocker == null
          ? button
          : Tooltip(
              key: ValueKey('categories.blocker.$id'),
              message: blocker,
              child: Semantics(hint: blocker, child: button),
            );
    } else {
      action = TextButton(
        key: ValueKey('categories.reopen.$id'),
        onPressed: busy ? null : onReopen,
        child: const Text('Reopen'),
      );
    }

    return Container(
      key: ValueKey('categories.row.$id'),
      color: changed ? c.marineTint : null,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x12,
        vertical: Space.x10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: Space.x8,
              runSpacing: Space.x4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  category.name,
                  style: t.bodyStrong.copyWith(
                    color: category.isActive ? null : c.muted,
                  ),
                ),
                if (!category.isActive)
                  const StatusBadge('CLOSED', tone: BadgeTone.warning),
              ],
            ),
          ),
          SizedBox(
            width: _Cols.price,
            child: MoneyInput(
              label: null,
              semanticLabel: '${category.name} price per night',
              controller: controller,
              fieldKey: ValueKey('price.$id'),
              errorText: error,
              enabled: canEdit && category.isActive,
              onChanged: (_) => onChanged(),
            ),
          ),
          if (canEdit)
            SizedBox(
              width: _Cols.was,
              child: changed
                  ? Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: Space.x12,
                      ),
                      child: Text(
                        'was ${_plain(category.pricePerNight)}',
                        key: ValueKey('price.was.$id'),
                        style: t.smallStrong.copyWith(color: c.marine),
                      ),
                    )
                  : null,
            ),
          SizedBox(
            width: _Cols.beds,
            child: Text(
              '${usage.activeBeds}',
              key: ValueKey('categories.beds.$id'),
              textAlign: TextAlign.end,
              style: t.mono,
            ),
          ),
          SizedBox(
            width: canEdit ? _Cols.action : _Cols.request,
            child: Align(alignment: Alignment.centerRight, child: action),
          ),
        ],
      ),
    );
  }
}

class _AddCategoryRow extends StatelessWidget {
  const _AddCategoryRow({
    required this.name,
    required this.price,
    required this.nameError,
    required this.priceError,
    required this.busy,
    required this.onAdd,
    required this.onCancel,
  });

  final TextEditingController name;
  final TextEditingController price;
  final String? nameError;
  final String? priceError;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.x12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LabeledField(
              label: 'New category',
              controller: name,
              fieldKey: const ValueKey('categories.newName'),
              errorText: nameError,
              helperText: 'Up to 30 characters',
              autofocus: true,
            ),
          ),
          const SizedBox(width: Space.x12),
          SizedBox(
            width: _Cols.price,
            child: MoneyInput(
              label: 'Price per night',
              controller: price,
              fieldKey: const ValueKey('categories.newPrice'),
              errorText: priceError,
            ),
          ),
          const SizedBox(width: Space.x12),
          Padding(
            padding: const EdgeInsets.only(top: Space.x24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton.primary(
                  key: const ValueKey('categories.confirmAdd'),
                  label: 'Add',
                  busy: busy,
                  onPressed: onAdd,
                ),
                const SizedBox(width: Space.x8),
                AppButton.secondary(
                  key: const ValueKey('categories.cancelAdd'),
                  label: 'Cancel',
                  onPressed: onCancel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
