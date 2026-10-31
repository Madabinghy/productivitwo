//
//  ProductivitwoWidgetBundle.swift
//  ProductivitwoWidget
//
//  Created by Emeric EDMOND on 25/05/2026.
//

import WidgetKit
import SwiftUI

@main
struct ProductivitwoWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProductivitwoWidget()   // Journée parfaite
        LaunchersWidget()
        NowWidget()
        ScheduleWidget()
        RoutinesWidget()
        FocusTaskWidget()       // Visées aujourd'hui
        WatchWidget()
        ProjectsWidget()        // Projet du moment
        // Live Activity « minuteur » (iOS 16.1+).
        if #available(iOS 16.1, *) {
            TimerLiveActivity()
        }
    }
}
