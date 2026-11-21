import HermesKit

extension TranscriptItem {
    /// What a Bot did on the way to a reply rather than said: tool steps, its to-do list and
    /// helpers, and a background command or helpers finishing. Settings › General can hide these
    /// (`AppPreferences.showToolActivityKey`); messages, Bot-to-Bot talk and routines' output stay.
    var isToolActivity: Bool {
        switch content {
        case .activity, .progress: true
        case .result(_, let detail): ProcessReport.parse(detail) != nil || HelperReport.parse(detail) != nil
        default: false
        }
    }
}
