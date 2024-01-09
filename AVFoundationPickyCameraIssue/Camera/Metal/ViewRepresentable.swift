//
//  ViewRepresentable.swift
//  PhotonCam
//
//  Created by Photon Juniper on 2023/10/27.
//
import SwiftUI

#if os(iOS) || os(tvOS)
public protocol ViewRepresentable: UIViewRepresentable {
    associatedtype ViewType = UIViewType
    func makeView(context: Context) -> ViewType
    func updateView(_ view: ViewType, context: Context)
}

extension ViewRepresentable {
    public func makeUIView(context: Context) -> ViewType {
        makeView(context: context)
    }
    
    public func updateUIView(_ uiView: ViewType, context: Context) {
        updateView(uiView, context: context)
    }
}
#elseif os(macOS)
public protocol ViewRepresentable: NSViewRepresentable {
    associatedtype ViewType = NSViewType
    func makeView(context: Context) -> ViewType
    func updateView(_ view: ViewType, context: Context)
}

extension ViewRepresentable {
    public func makeNSView(context: Context) -> ViewType {
        makeView(context: context)
    }
    
    public func updateNSView(_ nsView: ViewType, context: Context) {
        updateView(nsView, context: context)
    }
}
#endif
