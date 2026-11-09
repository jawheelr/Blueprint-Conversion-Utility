import SwiftUI
struct AboutView:View{@Environment(\.dismiss)var dismiss;var body:some View{VStack(spacing:14){AppIconView().frame(width:112,height:112);Text("Blueprint Conversion Utility").font(.largeTitle.bold());Text("Version 3.5.0");Text("Created by Jarred Wheeler");Button("Done"){dismiss()}}.padding().frame(width:460,height:390)}}
