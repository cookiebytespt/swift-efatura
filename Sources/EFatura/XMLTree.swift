import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A minimal XML tree. Names are local names: prefixes are dropped, because AT's
/// responses are matched by element name and the prefixes it uses are not guaranteed.
final class XMLNode {
    let name: String
    var text = ""
    var children: [XMLNode] = []

    init(name: String) {
        self.name = name
    }

    func child(_ name: String) -> XMLNode? {
        children.first { $0.name == name }
    }

    func children(named name: String) -> [XMLNode] {
        children.filter { $0.name == name }
    }

    /// Depth-first search, including the node itself.
    func first(named name: String) -> XMLNode? {
        if self.name == name { return self }
        for child in children {
            if let found = child.first(named: name) { return found }
        }
        return nil
    }

    /// The trimmed text of a child, or nil when the child is absent or empty.
    func value(_ name: String) -> String? {
        guard let text = child(name)?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }

    static func parse(_ data: Data) throws -> XMLNode {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = builder.root else {
            let reason = parser.parserError.map { "\($0)" } ?? "no root element"
            throw EFaturaError.malformedResponse("not XML: \(reason)")
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLNode?
        var stack: [XMLNode] = []

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
            let node = XMLNode(name: local)
            if let parent = stack.last {
                parent.children.append(node)
            } else {
                root = node
            }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            stack.removeLast()
        }
    }
}
