import 'package:cloud_functions/cloud_functions.dart';

class AnnulmentCandidate {
  AnnulmentCandidate(Map<String, dynamic> data)
    : id = data['id'] as String,
      personId = data['personId'] as String,
      periodId = data['periodId'] as String,
      name = data['name'] as String,
      status = data['status'] as String,
      version = (data['version'] as num).toInt(),
      revision = (data['revision'] as num).toInt();
  final String id, personId, periodId, name, status;
  final int version, revision;
  bool get canAnnul => status != 'finalized' && status != 'annulled';
}

typedef AnnulmentPage = ({List<AnnulmentCandidate> items, String? next});
typedef AnnulmentLookup = Future<AnnulmentPage> Function(
  String period,
  String? after,
);

Future<AnnulmentPage> lookupAnnulments(String period, String? after) async {
  final response = await FirebaseFunctions.instance
      .httpsCallable('findDeclarationsForAnnulment')
      .call({'periodId': period, 'after': after});
  final data = Map<String, dynamic>.from(response.data as Map);
  return (
    items: (data['declarations'] as List)
        .map((row) => AnnulmentCandidate(Map<String, dynamic>.from(row as Map)))
        .toList(),
    next: data['next'] as String?,
  );
}
