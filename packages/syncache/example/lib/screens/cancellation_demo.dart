import 'dart:async';

import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

import '../models/user.dart';
import '../services/cache.dart';
import '../services/fake_api.dart';

/// Demonstrates CancellationToken for cancelling in-flight requests.
///
/// This screen shows how to:
/// 1. Pass a CancellationToken to cache.get()
/// 2. Cancel the request before it completes
/// 3. Handle CancelledException gracefully
class CancellationDemoScreen extends StatefulWidget {
  const CancellationDemoScreen({super.key});

  @override
  State<CancellationDemoScreen> createState() => _CancellationDemoScreenState();
}

class _CancellationDemoScreenState extends State<CancellationDemoScreen> {
  CancellationToken? _currentToken;
  User? _user;
  bool _isLoading = false;
  String? _error;
  List<String> _events = [];

  @override
  void dispose() {
    _currentToken?.cancel();
    super.dispose();
  }

  void _addEvent(String event) {
    setState(() {
      _events = [
        '${DateTime.now().toString().substring(11, 19)}: $event',
        ..._events.take(14),
      ];
    });
  }

  Future<void> _startRequest() async {
    _currentToken?.cancel();

    final token = CancellationToken();
    _currentToken = token;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    _addEvent('Starting request...');
    await userCache.invalidate('user:cancellation-demo');

    try {
      final user = await userCache.get(
        key: 'user:cancellation-demo',
        fetch: (_) => fakeApi.fetchUser(),
        policy: Policy.networkOnly,
        cancel: token,
      );

      if (!mounted) return;

      setState(() {
        _user = user;
        _isLoading = false;
      });
      _addEvent('Request completed successfully');
    } on CancelledException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _addEvent('Request was cancelled');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _addEvent('Request failed: $e');
    }
  }

  void _cancelRequest() {
    if (_currentToken != null && !_currentToken!.isCancelled) {
      _addEvent('Cancelling request...');
      _currentToken!.cancel();
    }
  }

  Future<void> _startMultipleRequests() async {
    _addEvent('Starting rapid requests (each cancels the previous)...');

    setState(() {
      _isLoading = true;
    });

    for (var i = 1; i <= 5; i++) {
      _currentToken?.cancel();

      final token = CancellationToken();
      _currentToken = token;
      final isLastRequest = i == 5;

      _addEvent('Request #$i started');

      // Unique keys avoid request deduplication
      final key = 'user:cancellation-demo:$i';

      userCache
          .get(
            key: key,
            fetch: (_) async {
              // Simulate a slower request
              await Future.delayed(const Duration(milliseconds: 500));
              return fakeApi.fetchUser();
            },
            policy: Policy.networkOnly,
            cancel: token,
          )
          .then((user) {
            if (!mounted) return;
            _addEvent('Request #$i completed');
            if (token == _currentToken) {
              setState(() {
                _user = user;
                _isLoading = false;
              });
            }
          })
          .catchError((Object error) {
            if (!mounted) return;
            if (error is CancelledException) {
              _addEvent('Request #$i cancelled');
            } else {
              _addEvent('Request #$i failed: $error');
            }
            if (isLastRequest && token == _currentToken) {
              setState(() {
                _isLoading = false;
              });
            }
          });

      if (!isLastRequest) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    _addEvent('Only the last request (#5) should complete');
  }

  @override
  Widget build(BuildContext context) {
    final tokenStatus = _currentToken == null
        ? 'No token'
        : _currentToken!.isCancelled
        ? 'Token cancelled'
        : 'Token active';

    return Scaffold(
      appBar: AppBar(title: const Text('Cancellation Token')),
      body: Column(
        children: [
          // Event log
          Container(
            height: 150,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.terminal,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Request Log',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _currentToken?.isCancelled == false
                              ? Colors.green.withValues(alpha: 0.2)
                              : Theme.of(context).colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tokenStatus,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _currentToken?.isCancelled == false
                                    ? Colors.green
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      final isCancelled = event.contains('cancelled');
                      final isCompleted = event.contains('completed');
                      final isFailed = event.contains('failed');

                      Color? textColor;
                      if (isCancelled) {
                        textColor = Colors.orange;
                      } else if (isCompleted) {
                        textColor = Colors.green;
                      } else if (isFailed) {
                        textColor = Colors.red;
                      }

                      return Text(
                        event,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color:
                              textColor ??
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // User info card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildUserContent(),
              ),
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _startRequest,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start Request'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? _cancelRequest : null,
                        icon: const Icon(Icons.cancel),
                        label: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _startMultipleRequests,
                  icon: const Icon(Icons.fast_forward),
                  label: const Text('Start 5 Rapid Requests'),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Info card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'CancellationToken',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use CancellationToken to cancel in-flight requests:\n\n'
                      '- Start a request, then cancel before completion\n'
                      '- "Rapid requests" shows how new requests cancel old ones\n'
                      '- Useful for search-as-you-type or navigation away',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserContent() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Column(
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Text('Error', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    if (_user == null) {
      return Center(
        child: Text(
          'Start a request to load user data',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            _user!.name[0],
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_user!.name, style: Theme.of(context).textTheme.titleMedium),
              Text(
                _user!.email,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
