import 'dart:async';

import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';

import '../models/user.dart';
import '../services/cache.dart';
import '../services/fake_api.dart';

/// Demonstrates RetryConfig for automatic retry with exponential backoff.
///
/// This screen shows how to:
/// 1. Configure RetryConfig with maxAttempts and delay
/// 2. See retry behavior on transient failures
/// 3. Use retryIf to filter which errors trigger retries
class RetryDemoScreen extends StatefulWidget {
  const RetryDemoScreen({super.key});

  @override
  State<RetryDemoScreen> createState() => _RetryDemoScreenState();
}

class _RetryDemoScreenState extends State<RetryDemoScreen> {
  User? _user;
  bool _isLoading = false;
  String? _error;
  List<String> _events = [];
  int _maxRetries = 3;
  bool _simulateErrors = true;
  int _attemptCount = 0;

  @override
  void dispose() {
    super.dispose();
  }

  void _addEvent(String event) {
    setState(() {
      _events = [
        '${DateTime.now().toString().substring(11, 19)}: $event',
        ..._events.take(19),
      ];
    });
  }

  Future<void> _loadWithRetry() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _attemptCount = 0;
    });

    _addEvent('Starting request with $_maxRetries retries...');

    // Invalidate to force fresh fetch
    await userCache.invalidate('user:retry-demo');

    try {
      final user = await userCache.get(
        key: 'user:retry-demo',
        fetch: (_) async {
          _attemptCount++;
          _addEvent('Attempt #$_attemptCount');

          // Simulate errors based on settings
          if (_simulateErrors && _attemptCount < 3) {
            await Future.delayed(const Duration(milliseconds: 300));
            throw Exception('Simulated network error (attempt $_attemptCount)');
          }

          return fakeApi.fetchUser();
        },
        policy: Policy.networkOnly,
        retry: RetryConfig(
          maxAttempts: _maxRetries,
          delay: (attempt) {
            final delay = Duration(milliseconds: 500 * (1 << attempt));
            _addEvent('  Waiting ${delay.inMilliseconds}ms before retry...');
            return delay;
          },
        ),
      );

      if (!mounted) return;

      setState(() {
        _user = user;
        _isLoading = false;
      });
      _addEvent('Request succeeded after $_attemptCount attempts');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _addEvent('Request failed after $_attemptCount attempts: $e');
    }
  }

  Future<void> _loadWithCustomRetryIf() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _attemptCount = 0;
    });

    _addEvent(
      'Starting with custom retryIf (only retries TimeoutException)...',
    );

    await userCache.invalidate('user:retry-demo');

    try {
      final user = await userCache.get(
        key: 'user:retry-demo',
        fetch: (_) async {
          _attemptCount++;
          _addEvent('Attempt #$_attemptCount');

          if (_attemptCount == 1) {
            throw TimeoutException('Request timed out');
          }

          return fakeApi.fetchUser();
        },
        policy: Policy.networkOnly,
        retry: RetryConfig(
          maxAttempts: 3,
          retryIf: (error) {
            final shouldRetry = error is TimeoutException;
            _addEvent('  retryIf: ${error.runtimeType} -> $shouldRetry');
            return shouldRetry;
          },
        ),
      );

      if (!mounted) return;

      setState(() {
        _user = user;
        _isLoading = false;
      });
      _addEvent('Request succeeded');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _addEvent('Request failed: $e');
    }
  }

  Future<void> _loadWithNoRetry() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _attemptCount = 0;
    });

    _addEvent('Starting with RetryConfig.none (no retries)...');

    await userCache.invalidate('user:retry-demo');

    try {
      final user = await userCache.get(
        key: 'user:retry-demo',
        fetch: (_) async {
          _attemptCount++;
          _addEvent('Attempt #$_attemptCount');

          if (_simulateErrors) {
            throw Exception('Simulated error');
          }

          return fakeApi.fetchUser();
        },
        policy: Policy.networkOnly,
        retry: RetryConfig.none,
      );

      if (!mounted) return;

      setState(() {
        _user = user;
        _isLoading = false;
      });
      _addEvent('Request succeeded');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _addEvent('Request failed immediately (no retry): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Retry Config')),
      body: Column(
        children: [
          // Event log
          Container(
            height: 180,
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
                        'Retry Log',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const Spacer(),
                      if (_attemptCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Attempts: $_attemptCount',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
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
                      final isRetry = event.contains('Waiting');
                      final isAttempt = event.contains('Attempt');
                      final isSuccess = event.contains('succeeded');
                      final isFailed = event.contains('failed');

                      Color? textColor;
                      if (isRetry) {
                        textColor = Colors.orange;
                      } else if (isSuccess) {
                        textColor = Colors.green;
                      } else if (isFailed) {
                        textColor = Colors.red;
                      } else if (isAttempt) {
                        textColor = Theme.of(context).colorScheme.primary;
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
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Settings
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settings',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text('Max retries: $_maxRetries'),
                              ),
                              Slider(
                                value: _maxRetries.toDouble(),
                                min: 0,
                                max: 5,
                                divisions: 5,
                                label: _maxRetries.toString(),
                                onChanged: _isLoading
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _maxRetries = value.toInt();
                                        });
                                      },
                              ),
                            ],
                          ),
                          SwitchListTile(
                            title: const Text('Simulate errors'),
                            subtitle: const Text('Fails first 2 attempts'),
                            value: _simulateErrors,
                            onChanged: _isLoading
                                ? null
                                : (value) {
                                    setState(() {
                                      _simulateErrors = value;
                                    });
                                  },
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _loadWithRetry,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('Load with Exponential Backoff'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _loadWithCustomRetryIf,
                          icon: const Icon(Icons.filter_alt),
                          label: const Text('Load with Custom retryIf'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _loadWithNoRetry,
                          icon: const Icon(Icons.block),
                          label: const Text('Load with No Retry'),
                        ),
                      ],
                    ),
                  ),

                  // Result display
                  if (_user != null || _error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        color: _error != null
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.green.withValues(alpha: 0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(
                                _error != null
                                    ? Icons.error
                                    : Icons.check_circle,
                                color: _error != null
                                    ? Colors.red
                                    : Colors.green,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _error ?? 'Loaded: ${_user?.name}',
                                  style: TextStyle(
                                    color: _error != null
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Info card
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
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
                                  'RetryConfig',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Configure automatic retry behavior:\n\n'
                              '- maxAttempts: number of retries after initial failure\n'
                              '- delay: function returning wait time (exponential backoff)\n'
                              '- retryIf: predicate to filter which errors trigger retry',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
