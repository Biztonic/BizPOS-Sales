import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final String id;
  final String userId;
  final String userName;
  final String userRole; // Sales Executive, Team Leader, Director
  final String? teamLeaderId; // The user's team leader (for SE approval chain)
  final String title;
  final String description;
  final double amount;
  final String status; // Pending, PartiallyApproved, Approved, Rejected
  final List<ExpenseApproval> approvals;
  final int requiredApprovals; // Total approvals needed
  final DateTime createdAt;
  final DateTime updatedAt;

  Expense({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userRole,
    this.teamLeaderId,
    required this.title,
    required this.description,
    required this.amount,
    this.status = 'Pending',
    this.approvals = const [],
    this.requiredApprovals = 2,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Expense.fromMap(Map<String, dynamic> map, String id) {
    final approvalsList = <ExpenseApproval>[];
    if (map['approvals'] != null) {
      for (var a in (map['approvals'] as List)) {
        approvalsList.add(ExpenseApproval.fromMap(a as Map<String, dynamic>));
      }
    }
    return Expense(
      id: id,
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userRole: map['userRole'] ?? 'Sales Executive',
      teamLeaderId: map['teamLeaderId'],
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      status: map['status'] ?? 'Pending',
      approvals: approvalsList,
      requiredApprovals: map['requiredApprovals'] ?? 2,
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userRole': userRole,
      'teamLeaderId': teamLeaderId,
      'title': title,
      'description': description,
      'amount': amount,
      'status': status,
      'approvals': approvals.map((a) => a.toMap()).toList(),
      'requiredApprovals': requiredApprovals,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Expense copyWith({
    String? status,
    List<ExpenseApproval>? approvals,
  }) {
    return Expense(
      id: id,
      userId: userId,
      userName: userName,
      userRole: userRole,
      teamLeaderId: teamLeaderId,
      title: title,
      description: description,
      amount: amount,
      status: status ?? this.status,
      approvals: approvals ?? this.approvals,
      requiredApprovals: requiredApprovals,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}

class ExpenseApproval {
  final String approverId;
  final String approverName;
  final String approverRole;
  final String decision; // Approved, Rejected
  final DateTime approvedAt;

  ExpenseApproval({
    required this.approverId,
    required this.approverName,
    required this.approverRole,
    required this.decision,
    DateTime? approvedAt,
  }) : approvedAt = approvedAt ?? DateTime.now();

  factory ExpenseApproval.fromMap(Map<String, dynamic> map) {
    return ExpenseApproval(
      approverId: map['approverId'] ?? '',
      approverName: map['approverName'] ?? '',
      approverRole: map['approverRole'] ?? '',
      decision: map['decision'] ?? 'Approved',
      approvedAt: Expense._parseDateTime(map['approvedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'approverId': approverId,
      'approverName': approverName,
      'approverRole': approverRole,
      'decision': decision,
      'approvedAt': Timestamp.fromDate(approvedAt),
    };
  }
}
