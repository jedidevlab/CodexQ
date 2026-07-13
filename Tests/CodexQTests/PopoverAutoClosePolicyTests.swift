import Testing
@testable import CodexQ

struct PopoverAutoClosePolicyTests {
    @Test("仅在全部刷新结束且没有交互时启动自动关闭")
    func schedulesOnlyWhenIdle() {
        #expect(PopoverAutoClosePolicy.shouldSchedule(
            isQuotaRefreshing: false,
            isTokenActivityRefreshing: false,
            activeInteractions: []
        ))
        #expect(!PopoverAutoClosePolicy.shouldSchedule(
            isQuotaRefreshing: true,
            isTokenActivityRefreshing: false,
            activeInteractions: []
        ))
        #expect(!PopoverAutoClosePolicy.shouldSchedule(
            isQuotaRefreshing: false,
            isTokenActivityRefreshing: true,
            activeInteractions: []
        ))
        for interaction in PopoverInteraction.allCases {
            #expect(!PopoverAutoClosePolicy.shouldSchedule(
                isQuotaRefreshing: false,
                isTokenActivityRefreshing: false,
                activeInteractions: [interaction]
            ))
        }
    }
}
