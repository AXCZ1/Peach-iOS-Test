import SwiftUI

struct FilterSheet: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var tag = ""
    @State private var performer = ""
    @State private var studio = ""
    @State private var studios: [PeachFacet] = []
    @State private var isLoadingIndex = false

    var body: some View {
        NavigationStack {
            Form {
                Section("搜索") {
                    TextField("片名、番号、演员、标签", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { apply() }
                }
                Section("筛选") {
                    if let facets = model.facets {
                        Picker("演员", selection: $performer) {
                            Text("全部").tag("")
                            ForEach(facets.performers) { facet in
                                Text("\(facet.key)（\(facet.count)）").tag(facet.key)
                            }
                        }
                        Picker("标签", selection: $tag) {
                            Text("全部").tag("")
                            ForEach(facets.tags) { facet in
                                Text("\(facet.key)（\(facet.count)）").tag(facet.key)
                            }
                        }
                    } else {
                        Text("正在读取筛选项…").foregroundStyle(.secondary)
                    }
                    if studios.isEmpty {
                        TextField("厂牌（可选）", text: $studio)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Picker("厂牌", selection: $studio) {
                            Text("全部").tag("")
                            ForEach(studios) { facet in
                                Text("\(facet.key)（\(facet.count)）").tag(facet.key)
                            }
                        }
                    }
                }
                Section("状态与排序") {
                    Picker("状态", selection: Binding(
                        get: { model.filter.state },
                        set: { model.filter.state = $0 }
                    )) {
                        ForEach(CatalogState.allCases) { state in
                            Text(state.label).tag(state)
                        }
                    }
                    Picker("排序", selection: Binding(
                        get: { model.filter.sort },
                        set: { model.filter.sort = $0 }
                    )) {
                        ForEach(CatalogSort.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                    if model.filter.sort.supportsDirection {
                        Toggle("升序", isOn: Binding(
                            get: { model.filter.ascending },
                            set: { model.filter.ascending = $0 }
                        ))
                    }
                }
                Section {
                    Button("清除全部筛选") {
                        query = ""
                        tag = ""
                        performer = ""
                        studio = ""
                        Task {
                            await model.clearFilter()
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PeachTheme.background)
            .navigationTitle("筛选与搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") { apply() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                query = model.filter.query
                tag = model.filter.tag ?? ""
                performer = model.filter.performer ?? ""
                studio = model.filter.studio ?? ""
                loadStudios()
            }
            .preferredColorScheme(.dark)
        }
    }

    private func apply() {
        model.filter.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        model.filter.tag = tag.isEmpty ? nil : tag
        model.filter.performer = performer.isEmpty ? nil : performer
        let s = studio.trimmingCharacters(in: .whitespacesAndNewlines)
        model.filter.studio = s.isEmpty ? nil : s
        Task {
            await model.reload()
            dismiss()
        }
    }

    private func loadStudios() {
        guard studios.isEmpty, !isLoadingIndex else { return }
        isLoadingIndex = true
        Task {
            defer { isLoadingIndex = false }
            studios = (try? await model.apiIndex(kind: "studios")) ?? []
        }
    }
}
