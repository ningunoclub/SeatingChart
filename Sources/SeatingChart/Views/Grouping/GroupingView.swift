import SwiftUI

/// The grouping tab: every control lives here, the overlay only displays.
struct GroupingView: View {
    @Environment(AppStore.self) private var store
    @State private var showingTeamNames = false

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            stage
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    GroupsExport.exportPDF(store: store)
                } label: {
                    Label(L("grouping.export_pdf"), systemImage: "arrow.down.document")
                }
                .disabled(store.grouping.groups.isEmpty)

                Button {
                    GroupingOverlayController.shared.toggle(store: store)
                } label: {
                    Label(store.grouping.isOverlayVisible ? L("grouping.hide_overlay")
                                                          : L("grouping.show_overlay"),
                          systemImage: "macwindow.on.rectangle")
                }
                .help(L("grouping.overlay_help"))
            }
        }
        .sheet(isPresented: $showingTeamNames) {
            TeamNamesSheet(model: store.grouping, plannedCount: plannedCount)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        @Bindable var grouping = store.grouping
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Picker(L("grouping.class"), selection: $grouping.classID) {
                    Text(L("chart.none")).tag(UUID?.none)
                    ForEach(store.classes) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .frame(maxWidth: 220)

                // The mock's "set either one" pair. A segmented picker instead of
                // two fields: only one of them can be in force, and this way the
                // two can never be left contradicting each other.
                Picker(L("grouping.sizing"), selection: $grouping.sizingMode) {
                    Text(L("grouping.number_of_groups")).tag(GroupSizingMode.groupCount)
                    Text(L("grouping.max_per_group")).tag(GroupSizingMode.maxPerGroup)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)

                switch grouping.sizingMode {
                case .groupCount:
                    Stepper(value: $grouping.groupCount, in: 1...GroupingModel.maxGroups) {
                        Text(L("grouping.count_value", grouping.groupCount)).monospacedDigit()
                    }
                    .fixedSize()
                case .maxPerGroup:
                    Stepper(value: $grouping.maxPerGroup, in: 1...GroupingModel.maxGroups) {
                        Text(L("grouping.per_group_value", grouping.maxPerGroup)).monospacedDigit()
                    }
                    .fixedSize()
                }

                Spacer()

                Button {
                    store.makeGroups()
                } label: {
                    Label(L("grouping.make"), systemImage: "person.2.badge.gearshape")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canMakeGroups)

                Button {
                    store.makeGroups()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!store.canMakeGroups)
                .help(L("grouping.make_again"))
            }

            HStack(spacing: 14) {
                Text(L("grouping.distribute_by"))

                Stepper(value: $grouping.quotaMale, in: 0...GroupingModel.maxQuota) {
                    Label(L("grouping.quota_male", grouping.quotaMale),
                          systemImage: Gender.male.symbolName)
                        .monospacedDigit()
                }
                .fixedSize()
                .help(L("grouping.quota_help"))

                Stepper(value: $grouping.quotaFemale, in: 0...GroupingModel.maxQuota) {
                    Label(L("grouping.quota_female", grouping.quotaFemale),
                          systemImage: Gender.female.symbolName)
                        .monospacedDigit()
                }
                .fixedSize()
                .help(L("grouping.quota_help"))

                Divider().frame(height: 16)

                Toggle(L("grouping.pick_representatives"), isOn: $grouping.pickRepresentatives)

                Button(L("grouping.team_names")) { showingTeamNames = true }
                    .help(L("grouping.team_names_help"))

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if store.grouping.missingMale > 0 || store.grouping.missingFemale > 0 {
                        Text(L("grouping.quota_short", store.grouping.missingMale,
                               store.grouping.missingFemale))
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var plannedCount: Int {
        store.grouping.plannedGroupCount(for: store.groupingClass?.students ?? [])
    }

    /// How the class splits, and what it is made of — the two numbers needed to
    /// tell in advance whether a quota can actually be met.
    private var hint: String {
        guard let students = store.groupingClass?.students, !students.isEmpty else {
            return L("grouping.no_class")
        }
        let tally = GroupDraw.tally(students)
        return L("grouping.plan", students.count, plannedCount) + "  ·  "
            + L("grouping.tally", tally.male, tally.female, tally.unspecified)
    }

    // MARK: - Preview of what the class sees

    @ViewBuilder
    private var stage: some View {
        if let schoolClass = store.groupingClass {
            if schoolClass.students.isEmpty {
                ContentUnavailableView(L("grouping.empty_class"), systemImage: "person.badge.plus",
                                       description: Text(L("grouping.empty_class_hint")))
            } else if store.grouping.groups.isEmpty {
                ContentUnavailableView(L("grouping.not_drawn"),
                                       systemImage: "person.2.badge.gearshape",
                                       description: Text(L("grouping.not_drawn_hint")))
            } else {
                GroupingOverlayView(cornerRadius: 20)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .frame(maxWidth: 720)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        } else {
            ContentUnavailableView(L("grouping.no_class"),
                                   systemImage: "person.2.badge.gearshape",
                                   description: Text(L("grouping.no_class_hint")))
        }
    }
}
