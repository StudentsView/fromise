//
//  DeviceActivityMonitorExtension.swift
//  FromiseMonitor
//
//  Created by Julio on 6/24/26.
//

import DeviceActivity
import ManagedSettings
import Foundation

// Optionally override any of the functions below.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    // 메인 앱과 같은 named store / App Group을 공유
    private let store = ManagedSettingsStore(named: .init("fromise.twoG"))
    private let groupID = "group.com.flmang.Fromise"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        // Handle the start of the interval.
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        guard let ud = UserDefaults(suiteName: groupID) else { return }
        // 허위/조기 종료 방어: 저장된 종료 시각보다 1분 이상 이른 콜백은 무시한다.
        // (탭 이동·앱 복귀 시 모니터링 재설정 과정의 stopMonitoring 콜백 등으로 잠금이 조기 해제되던 결함 차단)
        if let end = ud.object(forKey: "twoG.endsAt") as? Date,
           Date() < end.addingTimeInterval(-60) {
            return
        }
        // 진짜 기간 종료 → 잠금 해제 + 만료 표시
        // (앱이 다음 실행 때 endsAt로 지속시간을 기록하고 원격 코드를 삭제하므로 endsAt는 지우지 않음)
        store.clearAllSettings()
        ud.set(true, forKey: "twoG.expired")
    }
    
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        
        // Handle the event reaching its threshold.
    }
    
    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        
        // Handle the warning before the interval starts.
    }
    
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        
        // Handle the warning before the interval ends.
    }
    
    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        
        // Handle the warning before the event reaches its threshold.
    }
}
