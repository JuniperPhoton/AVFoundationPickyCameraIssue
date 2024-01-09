//
//  ContentView.swift
//  AVFoundationPickyCameraIssue
//
//  Created by Photon Juniper on 2024/1/9.
//

import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = MainViewModel()
    
    var body: some View {
        VStack {
            CameraSettingsView(cameraSettings: viewModel.cameraSettings)
            MetalView(renderer: viewModel.renderer, enableSetNeedsDisplay: false)
            CameraControlView(viewModel: viewModel)
        }.onChange(of: scenePhase) { scenePhase in
            switch scenePhase {
            case .active:
                Task {
                    await viewModel.setupCamera()
                }
            case .background:
                Task {
                    await viewModel.stopCamera()
                }
            default:
                break
            }
        }
    }
}

struct CameraControlView: View {
    let viewModel: MainViewModel
    
    var body: some View {
        HStack {
            Button {
                Task {
                    await viewModel.capture()
                }
            } label: {
                Circle().fill(Color.white)
                    .frame(width: 60, height: 60)
            }
        }
    }
}

struct CameraSettingsView: View {
    @ObservedObject var cameraSettings: CameraSettings
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                Button {
                    cameraSettings.useRaw.toggle()
                } label: {
                    Text(cameraSettings.useRaw ? "RAW on" : "RAW off")
                }
                
                Button {
                    cameraSettings.fixRawShift.toggle()
                } label: {
                    Text(cameraSettings.fixRawShift ? "Fix Raw shift on" : "Fix Raw shift off")
                }
            }.buttonStyle(.borderedProminent)
        }
    }
}
