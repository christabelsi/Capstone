
String workflowStatusLabel(String? status) {
  switch (status) {
    case 'pending':
    case 'in_progress':
      return 'In progress';
    case 'completed':
      return 'Completed';
    case 'needs_review':
      return 'Needs review';
    case 'not_started':
      return 'Not started';
    case 'todo':
      return 'To do';
    case 'done':
      return 'Done';
    default:
      return status?.replaceAll('_', ' ') ?? 'In progress';
  }
}

String proposalStatusLabel(String? proposalStatus) {
  switch (proposalStatus) {
    case 'pending':
      return 'Pending approval';
    case 'approved':
      return 'Approved';
    case 'rejected':
      return 'Rejected';
    default:
      return proposalStatus ?? 'Approved';
  }
}
