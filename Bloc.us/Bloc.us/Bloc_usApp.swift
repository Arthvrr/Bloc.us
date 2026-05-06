//
//  Bloc_usApp.swift
//  Bloc.us
//
//  Created by Arthur Louette on 06/05/2026.
//

import SwiftUI

@main
struct Bloc_usApp: App {
    // On crée l'AppData ICI pour pouvoir le partager entre la fenêtre principale et la barre des menus
    @StateObject private var sharedData = AppData()

    var body: some Scene {
        // Ta fenêtre d'application classique
        WindowGroup {
            ContentView(appData: sharedData)
        }
        
        // ✨ LA MAGIE EST ICI : Le widget de la barre des menus
        MenuBarExtra("Bloc.us", systemImage: "graduationcap.fill") {
            MenuBarView(appData: sharedData)
        }
        // Le mode "window" permet d'afficher notre vue personnalisée plutôt qu'un menu déroulant texte basique
        .menuBarExtraStyle(.window)
    }
}
