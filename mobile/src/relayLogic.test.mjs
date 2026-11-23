// Run with `npm test` (Node's built-in test runner strips the TypeScript types).
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  addPendingDelivery,
  getUrlSecurityWarning,
  isPrivateNetworkUrl,
  isValidE164,
  normalizeSocketUrl,
  resultsFromLogs,
} from './relayLogic.ts';

test('normalizeSocketUrl accepts the endpoint with or without /websocket', () => {
  for (const input of [
    'wss://sms.example.com/phone',
    'wss://sms.example.com/phone/',
    'wss://sms.example.com/phone/websocket',
    ' wss://sms.example.com/phone/websocket/ ',
  ]) {
    assert.equal(normalizeSocketUrl(input), 'wss://sms.example.com/phone');
  }
});

test('resultsFromLogs answers server retries after an app restart', () => {
  const logs = [
    { id: 'msg_c', maskedRecipient: 'x', status: 'delivered', timestamp: 3 },
    { id: 'msg_b', maskedRecipient: 'x', status: 'failed', error: 'No service', timestamp: 2 },
    { id: 'msg_a', maskedRecipient: 'x', status: 'sent', timestamp: 1 },
  ];

  const results = resultsFromLogs(logs);

  assert.deepEqual(results.get('msg_a'), { status: 'sent', error: null });
  assert.deepEqual(results.get('msg_b'), { status: 'failed', error: 'No service' });
  // A delivered SMS was sent
  assert.deepEqual(results.get('msg_c'), { status: 'sent', error: null });
  // Oldest first, so trimming the map drops the oldest result
  assert.deepEqual([...results.keys()], ['msg_a', 'msg_b', 'msg_c']);
});

test('addPendingDelivery deduplicates and stays bounded', () => {
  let pending = addPendingDelivery([], 'a');
  pending = addPendingDelivery(pending, 'a');
  assert.deepEqual(pending, ['a']);

  pending = addPendingDelivery(['a', 'b', 'c'], 'd', 3);
  assert.deepEqual(pending, ['b', 'c', 'd']);
});

test('isValidE164', () => {
  assert.equal(isValidE164('+254712345678'), true);
  assert.equal(isValidE164('+254 712-345 678'), true);
  assert.equal(isValidE164('0712345678'), false);
  assert.equal(isValidE164('+0712345678'), false);
});

test('ws:// is only allowed without a warning on private networks', () => {
  assert.equal(isPrivateNetworkUrl('ws://192.168.1.5:4000/phone/websocket'), true);
  assert.equal(isPrivateNetworkUrl('ws://172.20.0.1/phone/websocket'), true);
  assert.equal(isPrivateNetworkUrl('ws://172.32.0.1/phone/websocket'), false);
  assert.equal(getUrlSecurityWarning('wss://api.example.com/phone/websocket'), null);
  assert.match(getUrlSecurityWarning('ws://api.example.com/phone/websocket'), /wss:\/\//);
});
