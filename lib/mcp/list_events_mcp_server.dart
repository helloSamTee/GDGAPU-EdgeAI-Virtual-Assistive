import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

import '../tool_handlers.dart';

const listEventsMcpPort = 8765;

Future<void> startListEventsMcpServer() async {
  // McpServer takes Implementation(name:, version:) as its ONE positional
  // argument, not name/version as named params on the constructor itself.
  final server = McpServer(
    Implementation(name: 'gdg-edge-ai-skills', version: '1.0.0'),
    options: McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );

  // `tool(...)` is deprecated — `registerTool(...)` is the current API and
  // is what actually accepts `inputSchema`.
  server.registerTool(
    'list_events',
    description: 'Lists calendar events for a date (default: today).',
    inputSchema: ToolInputSchema(properties: {'date': JsonSchema.string()}),
    // callback signature is (Map args, extra) — matches ToolCallback's
    // expected type, unlike the named-arg version that caused the
    // argument_type_not_assignable error.
    callback: (args, extra) async {
      final result = await ToolHandlers.listEvents(args);
      return CallToolResult(content: [TextContent(text: jsonEncode(result))]);
    },
  );

  final transport = StreamableHTTPServerTransport(
    options: StreamableHTTPServerTransportOptions(),
  );
  await server.connect(transport);

  final httpServer = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    listEventsMcpPort,
  );

  await for (final request in httpServer) {
    if (request.uri.path == '/mcp') {
      await transport.handleRequest(request);
    } else {
      request.response.statusCode = 404;
      await request.response.close();
    }
  }
}
