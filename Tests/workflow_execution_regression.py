from pathlib import Path
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
ui=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
models=Path('Sources/BlueprintCreator/TakeoverModels.swift').read_text()
checks={
'final action uses workflow dispatcher':'Task { await model.performGuidedFinalAction(deploymentIntent:' in ui,
'final action no longer calls generate':'Button(finalButtonTitle)' in ui and 'model.generate()' not in ui,
'takeover preview dispatch':'await runTakeoverImport(dryRun: dryRunEnabled, automatic: false, deploymentIntent: deploymentIntent)' in app,
'standard real dispatch':'requestCreate()' in app,
'explicit run model':'enum BlueprintRunStage' in models and '@Published var runStage' in app,
'current run completion set':'@Published var completedRunStages' in app,
'busy duplicate guard':'guard !busy else { return }' in app and '|| model.busy' in ui,
'interactive progress':'ForEach(expectedStages' in ui and 'ProgressView()' in ui,
'advanced activity':'jamf-cli Activity' in ui and 'model.takeoverRawOutput' in ui,
'failure logs':'model.runStage == .failed' in ui and 'model.showLogs = true' in ui,
'dry run distinction':'Dry-run preview completed. No Blueprint was created.' in app,
'configuration profile empty state':'← Select a Configuration Profile' in ui,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} workflow execution checks')
for p in Path('Sources/BlueprintCreator').glob('*.swift'):
 s=p.read_text(); assert s.count('{')==s.count('}'),p
print('PASS: source brace balance')
