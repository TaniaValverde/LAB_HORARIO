import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/errors/user_error.dart';
import '../domain/entities/declaration.dart';

class DeclarationList extends StatefulWidget {
  const DeclarationList({
    super.key,
    required this.watch,
    required this.onOpen,
    this.busy = false,
    this.mobileLab = false,
  });
  final Stream<List<Declaration>> Function() watch;
  final void Function(Declaration) onOpen;
  final bool busy;
  final bool mobileLab;
  @override
  State<DeclarationList> createState() => _DeclarationListState();
}

class _DeclarationListState extends State<DeclarationList> {
  late Stream<List<Declaration>> _items;
  @override
  void initState() {
    super.initState();
    _items = _watch();
  }

  Stream<List<Declaration>> _watch() {
    var received = false;
    return widget
        .watch()
        .map((items) {
          received = true;
          return items;
        })
        .timeout(
          const Duration(seconds: 15),
          onTimeout: (sink) {
            if (!received) {
              sink.addError(
                StateError(
                  'La lista tardó demasiado en responder. Pulse Actualizar lista.',
                ),
              );
            }
          },
        );
  }

  void _reload() => setState(() => _items = _watch());
  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton.icon(
        onPressed: widget.busy ? null : _reload,
        icon: const Icon(Icons.refresh),
        label: const Text('Actualizar lista'),
      ),
      StreamBuilder<List<Declaration>>(
        stream: _items,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              children: [
                Text(userError(snapshot.error!)),
                TextButton(onPressed: _reload, child: const Text('Reintentar')),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aún no tiene declaraciones.'),
              ),
            );
          }
          return Column(
            children: snapshot.data!
                .map(
                  (d) => Card(
                    child: ListTile(
                      isThreeLine: true,
                      title: Text(
                        'Período ${d.periodId} · Versión ${d.version}',
                      ),
                      subtitle: Text(
                        '${_status(d.status)}\n${d.status == DeclarationStatus.validated ? (widget.mobileLab ? 'Validación completada.' : 'Lista para continuar al módulo de firmas') : 'Creada: ${d.createdAt.toLocal().toString().split(' ').first}'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: widget.busy ? null : () => widget.onOpen(d),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    ],
  );
  String _status(DeclarationStatus s) => s.label;
}
