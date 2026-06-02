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
        ProductivitwoWidget()
        ScheduleWidget()
        RoutinesWidget()
        ProjectsWidget()
    }
}
