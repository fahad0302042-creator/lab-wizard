import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/error_text.dart';
import '../../inventory/domain/item_view.dart';
import '../../inventory/domain/models.dart';
import '../data/order_list.dart';

/// The plan is a draft, not an inventory movement or a saved purchase order.
class OrderPlanScreen extends StatefulWidget {
  const OrderPlanScreen({required this.items, super.key});
  final List<ItemView> items;

  @override
  State<OrderPlanScreen> createState() => _OrderPlanScreenState();
}

class _OrderPlanScreenState extends State<OrderPlanScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _amounts;
  late final Map<String, TextEditingController> _notes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amounts = {for (final i in widget.items) i.id: TextEditingController()};
    _notes = {for (final i in widget.items) i.id: TextEditingController()};
  }

  @override
  void dispose() {
    for (final controller in [..._amounts.values, ..._notes.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _share({required bool pdf}) async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final plan = {
      for (final item in widget.items)
        item.id: OrderPlanEntry(
          amount: double.tryParse(_amounts[item.id]!.text.trim()),
          note: _notes[item.id]!.text.trim(),
        ),
    };
    setState(() => _busy = true);
    try {
      if (pdf) {
        await Printing.sharePdf(
          bytes: await orderListPdf(widget.items, plan: plan),
          filename: 'order-list.pdf',
        );
      } else {
        await SharePlus.instance.share(
          ShareParams(text: orderListText(widget.items, plan: plan)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plan an order')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Add an optional amount and note for each item. This draft does '
            'not change stock and is not saved after you leave.',
          ),
          const SizedBox(height: 16),
          for (final item in widget.items) ...[
            Text(item.name, style: Theme.of(context).textTheme.titleMedium),
            Text('${formatQuantity(item.quantity)} ${item.unit} on shelf'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amounts[item.id],
              enabled: !_busy,
              keyboardType: TextInputType.numberWithOptions(
                decimal: !item.piecewise,
              ),
              decoration: InputDecoration(
                labelText: 'Amount to order (optional)',
                suffixText: item.unit,
              ),
              validator: (text) {
                if (text == null || text.trim().isEmpty) return null;
                final amount = double.tryParse(text.trim());
                if (amount == null || !amount.isFinite || amount <= 0) {
                  return 'Enter an amount above zero';
                }
                if (item.piecewise && amount != amount.roundToDouble()) {
                  return 'Enter a whole number';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _notes[item.id],
              enabled: !_busy,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 18),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : () => _share(pdf: false),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Share as a message'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _share(pdf: true),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Share as PDF'),
          ),
        ],
      ),
    ),
  );
}
