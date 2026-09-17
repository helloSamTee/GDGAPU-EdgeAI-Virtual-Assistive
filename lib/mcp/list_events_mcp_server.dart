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
    'list-events',
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

  httpServer.listen((request) async {
    if (request.uri.path == '/mcp') {
      await transport.handleRequest(request);
    } else {
      request.response.statusCode = 404;
      await request.response.close();
    }
  });

  print('✅ MCP Server is listening on port $listEventsMcpPort');
  // await for (final request in httpServer) {
  //   if (request.uri.path == '/mcp') {
  //     await transport.handleRequest(request);
  //   } else {
  //     request.response.statusCode = 404;
  //     await request.response.close();
  //   }
  // }

  // WAIT 1 SECOND FOR THE SERVER TO SPIN UP, THEN RUN THE TEST:
  Future.delayed(const Duration(seconds: 1), () {
    debugCheckMcpServer();
  });
}

// Add this to the bottom of list_events_mcp_server.dart
Future<void> debugCheckMcpServer() async {
  print('🔍 [Debug Client] Pinging MCP Server...');

  // 1. Create a raw MCP Client
  final client = McpClient(
    Implementation(name: 'debug-test-client', version: '1.0.0'),
  );

  // 2. Set up the transport to point to your local server
  final clientTransport = StreamableHttpClientTransport(
    Uri.parse('http://127.0.0.1:$listEventsMcpPort/mcp'),
  );

  try {
    // 3. Connect (This automatically handles the mandatory 'initialize' handshake!)
    await client.connect(clientTransport);
    print('🤝 [Debug Client] Handshake complete!');

    // 4. Request the tools list
    final response = await client.listTools(); //ListToolsRequest());

    // 5. Print the tools exactly as the server broadcasts them
    final tools = response.tools;
    if (tools.isEmpty) {
      print('⚠️ [Debug Client] Server is running, but returned 0 tools.');
    } else {
      print('✅ [Debug Client] Server is broadcasting ${tools.length} tool(s):');
      for (final tool in tools) {
        print('   - Tool Name: ${tool.name}');
        print('     Description: ${tool.description}');
        // You can even print tool.inputSchema to see the JSON rules!
      }
    }
  } catch (e) {
    print('❌ [Debug Client] Error: $e');
  }
}
