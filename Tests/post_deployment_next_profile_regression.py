from pathlib import Path
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
ui=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
checks={
'cancel prior evaluation':'takeoverEvaluationTask?.cancel()' in app,
'dry run reset':'dryRunEnabled = true' in app,
'deployment intent reset':'deploymentIntent = .createOnly' in app,
'recommendation reset':'recommendedApproach = .analyzing' in app,
'verdict reset':'takeoverVerdict = .notEvaluated' in app,
'run state reset':'runStage = .idle' in app and 'completedRunStages = []' in app,
'group reset':'selectedGroup = nil' in app,
'fresh scheduling':'workflowMode = takeoverCapabilities.commandAvailable ? .takeover : .standard' in app and 'scheduleAutomaticTakeoverEvaluation()' in app,
'setup reset':'step = 0' in ui,
'alternatives collapse':'showManualApproach = false' in ui,
'no blank picker while analyzing':'showManualApproach && model.selectedApproach != .analyzing' in ui,
'change approach hidden while analyzing':'if model.recommendedApproach != .analyzing' in ui,
}
for n,v in checks.items(): assert v,n
print(f'PASS: {len(checks)} post-deployment next-profile checks')
