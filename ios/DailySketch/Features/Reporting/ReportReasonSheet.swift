import SwiftUI

struct ReportReasonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ReportViewModel
    var onOfferBlock: ((UUID) -> Void)?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                .background(AppColors.background.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .pickingReason, .confirming, .failed:
            reasonList
        case .success(let message):
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColors.success)
                Text(message)
                    .font(AppTypography.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Reports are private.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                if model.offeredBlockAfterReport, let userId = model.blockableUserId {
                    PrimaryButton(title: "Block User") {
                        onOfferBlock?(userId)
                        dismiss()
                    }
                }
                SecondaryButton(title: "Done") { dismiss() }
            }
            .padding(AppSpacing.screenHorizontal)
        }
    }

    private var reasonList: some View {
        List {
            Section {
                Text("Reports are private. Moderators review them without sharing details back to you.")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .listRowBackground(AppColors.surfaceSecondary)
            }
            Section("Reason") {
                ForEach(ReportReasonKind.allCases) { reason in
                    Button {
                        model.selectedReason = reason
                    } label: {
                        HStack {
                            Text(reason.title)
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if model.selectedReason == reason {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.primary)
                            }
                        }
                    }
                    .accessibilityLabel(reason.title)
                }
            }
            if model.selectedReason == .other {
                Section("Details") {
                    TextField("Add a short note", text: $model.notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            if case .failed(let message) = model.phase {
                Section {
                    Text(message)
                        .foregroundStyle(AppColors.danger)
                }
            }
            Section {
                PrimaryButton(
                    title: model.isSubmitting ? "Submitting…" : "Submit Report",
                    action: { Task { await model.submit() } },
                    isDisabled: !model.canSubmit || model.isSubmitting
                )
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }
}
