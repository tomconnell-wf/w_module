// Copyright 2017 Workiva Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@TestOn('vm || browser')
import 'dart:async';

import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:w_common/json_serializable.dart' show JsonSerializable;
import 'package:w_module/serializable_module.dart';
import 'package:w_module/w_module.dart';

DispatchKey dispatchKey = new DispatchKey('serializable');

class TestSerializableModule extends SerializableModule {}

@Reflectable()
class TestSerializable extends JsonSerializable {
  String _name;
  TestSerializable();
  TestSerializable.fromJson(Map<String, dynamic> json) {
    _name = json['name'];
  }

  @override
  Map<String, dynamic> toJson() {
    return {'name': _name};
  }
}

@Reflectable()
class TestApi {
  bool addCalled = false;
  bool removeCalled = false;

  void add() {
    addCalled = true;
  }

  void remove(TestSerializable serializable) {
    removeCalled = true;
  }
}

class TestEvents extends Object with SerializableEvents {
  final SerializableEvent testEvent =
      new SerializableEvent('testEvent', dispatchKey);

  @override
  List<SerializableEvent> get allEvents => [testEvent];
}

class MockSerializableBus extends Mock implements SerializableBus {}

class MockSerializableModule extends Mock implements SerializableModule {}

class MockSerializableEvent extends Mock implements SerializableEvent {}

class MockTestEvents extends Mock implements TestEvents {}

class MockBridge<T> extends Bridge<T> with Mock {
  // ignore: close_sink
  final StreamController _broadcastSerializedEventStreamController =
      new StreamController.broadcast();
  // ignore: close_sink
  final StreamController _handleSerializedApiCallStreamController =
      new StreamController.broadcast();

  MockBridge(Stream<Map> apiCallReceived) : super(apiCallReceived);

  @override
  void broadcastSerializedEvent(Map event) {
    _broadcastSerializedEventStreamController.add(event);
  }

  @override
  void handleSerializedApiCall(T apiCall) {
    _handleSerializedApiCallStreamController.add(apiCall);
  }

  Stream get broadcastSerializedEventStream =>
      _broadcastSerializedEventStreamController.stream;

  Stream get handleSerializedApiCallStream =>
      _handleSerializedApiCallStreamController.stream;
}

void main() {
  group('SerializableModule', () {
    SerializableModule module;

    setUp(() {
      module = new TestSerializableModule();
    });

    test('should return null for serializableKey by default', () async {
      expect(module.serializableKey, isNull);
    });

    test('should return null for events by default', () async {
      expect(module.events, isNull);
    });
  });

  group('SerializeableEvent', () {
    SerializableEvent event;
    String eventKey = 'eventKey';

    setUp(() {
      event = new SerializableEvent(eventKey, dispatchKey);
    });

    test('should have an eventKey', () async {
      expect(event.eventKey, eventKey);
    });
  });

  group('SerializableEvents', () {
    TestEvents events;

    setUp(() {
      events = new TestEvents();
    });

    test('should provide a list of all events', () async {
      expect(events.allEvents, [events.testEvent]);
    });
  });

  group('SerializableBus', () {
    Completer lifecycleCompleter;
    StreamController willLoadController;
    StreamController didLoadController;
    StreamController willUnloadController;
    StreamController didUnloadController;
    StreamController bridgeEventController;

    SerializableBus bus;
    SerializableEvent event;

    MockSerializableModule module;
    MockTestEvents events;
    TestApi api;
    MockBridge bridge;

    final String serializableKey = 'serializableKey';
    final String testEventKey = 'testEvent';

    setUp(() {
      lifecycleCompleter = new Completer();
      bus = new SerializableBus();
      module = new MockSerializableModule();
      event = new SerializableEvent(testEventKey, dispatchKey);
      events = new MockTestEvents();
      api = new TestApi();

      willLoadController = new StreamController.broadcast();
      didLoadController = new StreamController.broadcast();
      willUnloadController = new StreamController.broadcast();
      didUnloadController = new StreamController.broadcast();
      bridgeEventController = new StreamController.broadcast();

      willLoadController.stream.listen((_) => lifecycleCompleter.complete());
      didLoadController.stream.listen((_) => lifecycleCompleter.complete());
      didUnloadController.stream.listen((_) => lifecycleCompleter.complete());
      willUnloadController.stream.listen((_) => lifecycleCompleter.complete());

      when(events.allEvents).thenReturn([event]);

      when(module.api).thenReturn(api);
      when(module.events).thenReturn(events);
      when(module.serializableKey).thenReturn(serializableKey);
      when(module.willLoad).thenReturn(willLoadController.stream);
      when(module.didLoad).thenReturn(didLoadController.stream);
      when(module.willUnload).thenReturn(willUnloadController.stream);
      when(module.didUnload).thenReturn(didUnloadController.stream);

      bridge = new MockBridge(bridgeEventController.stream);

      bus.registerModule(module);
      bus.bridge = bridge;
    });

    test('should provide a singleton', () async {
      expect(SerializableBus.sharedBus, isNotNull);
      expect(SerializableBus.sharedBus, new isInstanceOf<SerializableBus>());
    });

    test('should reset the bus', () async {
      bus.reset();
      expect(bus.registeredModules.keys.length, equals(0));
      expect(bus.bridge, isNull);
    });

    test('should not allow a bridge to be set to null', () async {
      bus.bridge = null;
      expect(bus.bridge, isNotNull);
    });

    test('should properly register modules and register for lifecycle events',
        () async {
      expect(bus.registeredModules[serializableKey], module);
      verify(module.willLoad);
      verify(module.didLoad);
      verify(module.willUnload);
      verify(module.didUnload);
    });

    test('should register for all module events', () async {
      Map<String, dynamic> expectedEvent = {
        'module': serializableKey,
        'event': testEventKey,
        'data': null
      };

      Completer eventCompleter = new Completer();

      willLoadController.add(null);

      await lifecycleCompleter.future;

      event.listen((_) {
        eventCompleter.complete();
      });

      bridge.broadcastSerializedEventStream
          .listen(expectAsync1((Map actualEvent) {
        expect(actualEvent, equals(expectedEvent));
      }));

      event.call(null, dispatchKey);
      await eventCompleter.future;
    });

    test('should fire the module willLoad event', () async {
      Map<String, dynamic> expectedEvent = {
        'module': serializableKey,
        'event': 'willLoad',
        'data': null
      };

      bridge.broadcastSerializedEventStream
          .listen(expectAsync1((Map actualEvent) {
        expect(actualEvent, equals(expectedEvent));
      }));

      willLoadController.add(null);
      await lifecycleCompleter.future;
    });

    test('should fire the module didLoad event', () async {
      Map<String, dynamic> expectedEvent = {
        'module': serializableKey,
        'event': 'didLoad',
        'data': null
      };

      bridge.broadcastSerializedEventStream
          .listen(expectAsync1((Map actualEvent) {
        expect(actualEvent, equals(expectedEvent));
      }));

      didLoadController.add(null);
      await lifecycleCompleter.future;
    });

    test('should fire the module willUnload event', () async {
      Map<String, dynamic> expectedEvent = {
        'module': serializableKey,
        'event': 'willUnload',
        'data': null
      };

      bridge.broadcastSerializedEventStream
          .listen(expectAsync1((Map actualEvent) {
        expect(actualEvent, equals(expectedEvent));
      }));

      willUnloadController.add(null);
      await lifecycleCompleter.future;
    });

    test('should fire the module didUnload event', () async {
      Map<String, dynamic> expectedEvent = {
        'module': serializableKey,
        'event': 'didUnload',
        'data': null
      };

      bridge.broadcastSerializedEventStream
          .listen(expectAsync1((Map actualEvent) {
        expect(actualEvent, equals(expectedEvent));
      }));

      didUnloadController.add(null);
      await lifecycleCompleter.future;
    });

    test('should not broadcast an event if the bridge is not set', () async {
      bus.reset();

      clearInteractions(bridge);
      didUnloadController.add(null);
      await lifecycleCompleter.future;

      verifyZeroInteractions(bridge);
    });

    test('should call correct api method', () async {
      Completer completer = new Completer();
      Map<String, dynamic> apiCall = {
        'module': serializableKey,
        'method': 'add',
        'data': []
      };

      bridgeEventController.stream.listen((_) => completer.complete());
      bridgeEventController.add(apiCall);

      await completer.future;

      expect(api.addCalled, isTrue);
    });

    test('should correctly serialize data and call api method', () async {
      Completer completer = new Completer();
      Map<String, dynamic> apiCall = {
        'module': serializableKey,
        'method': 'remove',
        'data': [
          {'name': 'Rob Stark'}
        ]
      };

      bridgeEventController.stream.listen((_) => completer.complete());
      bridgeEventController.add(apiCall);

      await completer.future;

      expect(api.removeCalled, isTrue);
    });

    test('should not call api method if paramater lengths are mismatched',
        () async {
      Completer completer = new Completer();
      Map<String, dynamic> apiCall = {
        'module': serializableKey,
        'method': 'remove',
        'data': [
          {'name': 'Rob Stark'},
          {'one': 'tomany'}
        ]
      };

      bridgeEventController.stream.listen((_) => completer.complete());
      bridgeEventController.add(apiCall);

      await completer.future;

      expect(api.removeCalled, isFalse);
    });

    tearDown(() async {
      await willLoadController.close();
      await didLoadController.close();
      await willUnloadController.close();
      await didUnloadController.close();
      await bridgeEventController.close();
    });
  });
}
