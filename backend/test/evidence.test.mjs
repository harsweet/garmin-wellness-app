import test from 'node:test';
import assert from 'node:assert/strict';
import { DemoCalendar } from '../demo-calendar.mjs';
import { WellnessService } from '../wellness-service.mjs';

test('a simulated timer remains explicitly simulated in persisted evidence', async () => {
  const calendar = new DemoCalendar({ now: () => Date.parse('2026-11-14T17:00:00Z') });
  const service = new WellnessService(calendar);
  await service.saveProfile({ preferredActivities: ['rest'], maxBreakMinutes: 2 });
  const { suggestion } = await service.suggestions();
  const accepted = await service.decide({ suggestionId: suggestion.id, decision: 'accept' });
  const activityId = accepted.activity.id;
  await service.start({ activityId });
  await assert.rejects(service.complete({ activityId, source: 'simulated_timer', elapsedSeconds: 1 }), error => error.httpStatus === 400);
  const reply = await service.complete({ activityId, source: 'simulated_timer', elapsedSeconds: 120 });
  assert.equal(reply.activity.completion.source, 'simulated_timer');
  assert.equal(calendar.wellnessState.sessions[activityId].completion.source, 'simulated_timer');
});
