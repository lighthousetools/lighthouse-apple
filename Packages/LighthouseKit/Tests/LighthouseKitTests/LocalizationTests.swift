import Foundation
import Testing

@testable import LighthouseKit

/// The language is global, and the app model sets it too, so these run with
/// the server suites rather than beside them.
extension ServerTests {
@Suite(.serialized) struct LocalizationTests {
    @Test func textsFollowTheLanguageAndKeepArguments() {
        Lang.current = .german
        defer { Lang.current = .english }
        #expect(tr("Needs you") == "Braucht dich")
        #expect(tr("%@ finished at %@", "Briefing", "07:30") == "Briefing war um 07:30 fertig")
        #expect(tr("Unknown text") == "Unknown text")
        #expect(statusName("limit_exceeded") == "Am Limit gestoppt")
        #expect(readableName("brain-ask") == "Frage ans Brain")
        Lang.current = .english
        #expect(tr("Needs you") == "Needs you")
        #expect(readableName("morning-brief") == "Morning brief")
    }

    @Test func translationsKeepTheirPlaceholders() {
        for (english, german) in germanStrings {
            let count = { (text: String) in text.components(separatedBy: "%@").count }
            #expect(count(english) == count(german), "\(english)")
        }
    }

    @Test func proposalsReadAsFields() {
        let input = JSONValue.object(["to_address": .string("a"), "count": .number(2), "ok": .bool(true)])
        let fields = input.fields
        #expect(fields.map(\.name) == ["Count", "Ok", "To address"])
        #expect(fields.map(\.value) == ["2", "true", "a"])
        #expect(JSONValue.string("x").fields.isEmpty)
    }

    @Test func eventsAreParsedAcrossLines() throws {
        var parser = EventParser()
        #expect(parser.feed("event: delta") == nil)
        #expect(parser.feed(#"data: {"text":"Hi"}"#) == nil)
        let parsed = parser.feed("")
        let event = try #require(parsed)
        #expect(event == ServerEvent(name: "delta", data: #"{"text":"Hi"}"#))
        #expect(parser.feed("") == nil)
        #expect(parser.feed(": keep alive") == nil)
        #expect(try Client.askEvent(event) == .delta("Hi"))
        #expect(throws: ClientError.server(status: 502, message: "no model")) {
            try Client.askEvent(ServerEvent(name: "failed", data: #"{"error":"no model"}"#))
        }
        #expect(try Client.askEvent(ServerEvent(name: "other", data: "")) == nil)
    }
}
}
