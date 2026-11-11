from pathlib import Path

src = Path('Sources/BlueprintCreator')
rules = (src / 'AdvisorRules.swift').read_text()
index = (src / 'AdvisorIndex.swift').read_text()
service = (src / 'AdvisorService.swift').read_text()
views = (src / 'AdvisorViews.swift').read_text()
model = (src / 'AppModel.swift').read_text()
content = (src / 'ContentView.swift').read_text()
app = (src / 'BlueprintCreatorApp.swift').read_text()
editor = (src / 'BlueprintGUIEditorView.swift').read_text()
review = (src / 'DeploymentReviewView.swift').read_text()
kb = (src / 'KnowledgeBaseView.swift').read_text()
cli = Path('Sources/BCUCLI/main.swift').read_text()
build = Path('build.sh').read_text()

advisor_files = {'rules': rules, 'index': index, 'service': service, 'views': views}
forbidden = ['unscopeProfile', 'createBlueprint', 'performDeployment', 'confirmUnscope',
             'requestCreateDistributeAndUnscope', 'takeoverRawOutput', 'platformSecret',
             'KeychainStore', 'stdout', 'rawOutput']

checks = {
    # Rules cover the messages jamf-cli 1.36.0 prints.
    'skipped payload rule': 'skipped payload type' in rules,
    'mcx rule': 'is not a standalone blueprints payload' in rules,
    'wrapper rule': 'kept in profile wrapper' in rules,
    'empty payload rule': 'removed empty payload' in rules,
    'rewrite rule': 'rewrote payload type' in rules,
    'os 26 rule': 'requires macos 26' in rules,
    'missing key rule': 'removed payload' in rules and 'requires' in rules,
    'takeover rules': 'takeover is not supported' in rules and 'takeover was not requested' in rules,
    'dry-run line ignored': '[dry-run] would create blueprint' in rules,
    'scope findings': all(term in rules for term in ['allDevices', 'individualDeviceCount', 'otherTargetCount', 'limitationCount', 'exclusionCount']),
    'redaction finding': 'redactedFieldCount' in rules,
    # Advice is read-only and never sees raw output or secrets.
    'advice is read-only': all(token not in text for token in forbidden for text in advisor_files.values()),
    # On-device AI is gated and macro-free so it builds with Xcode and Command Line Tools.
    'foundation models gated': '#if canImport(FoundationModels)' in service and '@available(macOS 26.0, *)' in service,
    'no macros': '@Generable' not in service and '@Guide' not in service,
    'model availability checked': 'SystemLanguageModel.default.availability' in service,
    'model told not to deploy': 'Never recommend deploying, unscoping or deleting' in service,
    'model timeout': 'withTimeout(seconds: 20)' in service,
    'rule-based fallback': 'builtIn(' in service and 'AdvisorSource.builtIn' in service or '.builtIn(reason' in service,
    # Retrieval is offline and version-matched.
    'embedding retrieval': 'NLEmbedding.sentenceEmbedding' in index,
    'no network in retrieval': 'URLSession' not in index and 'URLSession' not in service,
    'bundled corpus only': 'subdirectory: "Advisor"' in index,
    'required terms filter': 'requiredTerms' in index and 'requiredTerms' in rules,
    # Wiring.
    'refresh guards stale results': 'func refreshAdvice()' in model and 'profileLoadGeneration == generation' in model,
    'advice cleared on select': 'adviceTask?.cancel(); advice = nil' in model,
    'sheet wired': 'AdvisorPanel()' in content,
    'menu item': 'Explain & Recommend' in app,
    'editor button': 'Explain & Recommend' in editor,
    'info buttons': 'AdvisorInfoButton(line: item)' in review,
    'logger category': 'static let ai' in (src / 'AppLogger.swift').read_text(),
    'knowledge base topic': 'case explain = "Explain & Recommend"' in kb,
    # Build pipeline.
    'cli subcommand': 'build-advisor-index' in cli and 'AdvisorIndexBuilder' in cli,
    'build step': 'build-advisor-index' in build and 'Contents/Resources/Advisor' in build,
    'license shipped': 'jamf-cli-LICENSE.txt' in build,
}
for name, ok in checks.items():
    assert ok, name
print(f'PASS: {len(checks)} advisor checks')
