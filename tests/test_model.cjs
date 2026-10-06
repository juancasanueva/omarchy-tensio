'use strict'
// Unit tests for Model.js. Run with: node tests/test_model.cjs
const assert = require('assert/strict')
const path = require('path')

const M = require(path.join(__dirname, '..', 'Model.js'))

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed += 1
  } catch (err) {
    console.error('FAIL ' + name)
    throw err
  }
}

// A fixed "now": Tuesday 6 October 2026, 12:00 local time.
const NOW = new Date(2026, 9, 6, 12, 0, 0, 0)
const PROFILE = 'p_0123456789ab'
const OTHER = 'p_ba9876543210'

function reading(at, sys, dia, pulse, extra) {
  return Object.assign({
    id: M.newId('r'), profileId: PROFILE, at, sys, dia, pulse,
    feeling: '', body: '', arm: '', note: ''
  }, extra || {})
}

test('categories at the boundaries', () => {
  assert.equal(M.categoryOf(129, 79), 'elevated')
  assert.equal(M.categoryOf(130, 79), 'stage1')
  assert.equal(M.categoryOf(120, 80), 'stage1')
  assert.equal(M.categoryOf(140, 89), 'stage2')
  assert.equal(M.categoryOf(139, 90), 'stage2')
  assert.equal(M.categoryOf(181, 70), 'severe')
  assert.equal(M.categoryOf(120, 121), 'severe')
  assert.equal(M.categoryOf(180, 120), 'stage2')
  assert.equal(M.categoryOf(89, 70), 'low')
  assert.equal(M.categoryOf(119, 59), 'low')
  assert.equal(M.categoryOf(100, 70), 'normal')
  assert.equal(M.categoryOf(90, 60), 'normal')
  assert.equal(M.categoryOf(119, 79), 'normal')
})

test('CATEGORIES is ordered and carries the display metadata', () => {
  assert.deepEqual(M.CATEGORIES.map(c => c.key), ['low', 'normal', 'elevated', 'stage1', 'stage2', 'severe'])
  assert.deepEqual(M.CATEGORIES.map(c => c.label), ['Low', 'Normal', 'Elevated', 'Stage 1', 'Stage 2', 'Severe'])
  assert.equal(M.CATEGORIES[3].longLabel, 'Stage 1 Hypertension')
  assert.equal(M.CATEGORIES[5].longLabel, 'Severe Hypertension')
  assert.deepEqual(M.CATEGORIES.map(c => c.color), ['#3b82f6', '#22c55e', '#eab308', '#f97316', '#ef4444', '#be123c'])
  assert.equal(M.CATEGORIES[1].description, 'Sys 90–119 And Dia 60–79')
  assert.equal(M.CATEGORIES[5].description, 'Sys>180 And/Or Dia>120')
  assert.match(M.SEVERE_WARNING, /^Hypertensive emergency:/)
  assert.equal(M.category('stage2').label, 'Stage 2')
  assert.equal(M.category('bogus').key, 'normal')
})

test('rangeStart covers today plus the previous days, from midnight', () => {
  assert.equal(M.rangeStart('7d', NOW).getTime(), new Date(2026, 8, 30, 0, 0, 0, 0).getTime())
  assert.equal(M.rangeStart('30d', NOW).getTime(), new Date(2026, 8, 7, 0, 0, 0, 0).getTime())
  assert.equal(M.rangeStart('all', NOW), null)
  assert.equal(M.rangeStart('garbage', NOW), null)
})

test('parseAt is strict about the YYYY-MM-DDTHH:MM shape', () => {
  assert.equal(M.parseAt('2026-10-06T07:33').getTime(), new Date(2026, 9, 6, 7, 33).getTime())
  assert.equal(M.parseAt('2026-10-06T07:33:00'), null)
  assert.equal(M.parseAt('2026-10-06 07:33'), null)
  assert.equal(M.parseAt('2026-13-06T07:33'), null)
  assert.equal(M.parseAt('2026-02-30T07:33'), null)
  assert.equal(M.parseAt('2026-10-06T24:00'), null)
  assert.equal(M.parseAt(''), null)
  assert.equal(M.parseAt(null), null)
  assert.equal(M.parseAt(20261006), null)
  assert.equal(M.toAt(new Date(2026, 9, 6, 7, 3)), '2026-10-06T07:03')
})

test('filterReadings keeps the profile and range, sorted ascending', () => {
  const list = [
    reading('2026-10-06T09:00', 120, 80, 70),
    reading('2026-09-30T08:00', 118, 76, 65),
    reading('2026-09-29T23:59', 117, 75, 64),
    reading('2026-10-01T08:00', 121, 81, 66, { profileId: OTHER }),
    reading('not-a-date', 121, 81, 66)
  ]
  const week = M.filterReadings(list, PROFILE, '7d', NOW)
  assert.deepEqual(week.map(r => r.at), ['2026-09-30T08:00', '2026-10-06T09:00'])
  const all = M.filterReadings(list, PROFILE, 'all', NOW)
  assert.deepEqual(all.map(r => r.at), ['2026-09-29T23:59', '2026-09-30T08:00', '2026-10-06T09:00'])
  assert.deepEqual(M.filterReadings(list, 'p_000000000000', 'all', NOW), [])
})

test('averages round and return nulls when empty', () => {
  assert.deepEqual(M.averages([]), { sys: null, dia: null, pulse: null, count: 0 })
  const avg = M.averages([
    reading('2026-10-06T09:00', 120, 80, 70),
    reading('2026-10-06T10:00', 125, 81, 71),
    reading('2026-10-06T11:00', 126, 82, 72)
  ])
  assert.deepEqual(avg, { sys: 124, dia: 81, pulse: 71, count: 3 })
})

test('distribution is aligned with CATEGORIES and reports integer percentages', () => {
  const dist = M.distribution([
    reading('2026-10-06T09:00', 100, 70, 70),
    reading('2026-10-06T10:00', 101, 71, 70),
    reading('2026-10-06T11:00', 135, 85, 70)
  ])
  assert.deepEqual(dist.map(d => d.key), M.CATEGORIES.map(c => c.key))
  assert.deepEqual(dist.map(d => d.count), [0, 2, 0, 1, 0, 0])
  assert.deepEqual(dist.map(d => d.pct), [0, 67, 0, 33, 0, 0])
  assert.deepEqual(M.distribution([]).map(d => d.pct), [0, 0, 0, 0, 0, 0])
})

test('groupByDay labels Today, Yesterday and older dates, most recent first', () => {
  const groups = M.groupByDay([
    reading('2026-10-03T07:30', 120, 80, 70),
    reading('2026-10-06T07:33', 120, 80, 70),
    reading('2026-10-06T21:10', 120, 80, 70),
    reading('2026-10-05T08:00', 120, 80, 70)
  ], NOW)
  assert.deepEqual(groups.map(g => g.key), ['2026-10-06', '2026-10-05', '2026-10-03'])
  assert.deepEqual(groups.map(g => g.label), ['Today', 'Yesterday', 'Sat, Oct 3'])
  assert.deepEqual(groups[0].readings.map(r => r.at), ['2026-10-06T21:10', '2026-10-06T07:33'])
})

test('formatting helpers', () => {
  assert.equal(M.formatTime('2026-10-06T07:33'), '7:33 AM')
  assert.equal(M.formatTime('2026-10-06T00:05'), '12:05 AM')
  assert.equal(M.formatTime('2026-10-06T12:00'), '12:00 PM')
  assert.equal(M.formatTime('2026-10-06T23:59'), '11:59 PM')
  assert.equal(M.formatDate('2026-10-06T07:33'), 'Oct 6, 2026')
  assert.equal(M.formatShortDate('2026-10-06T07:33'), 'Oct 6')
  assert.equal(M.formatDateTime('2026-10-06T07:33'), 'Oct 6, 2026 at 7:33 AM')
  assert.equal(M.formatDate('garbage'), '')
})

test('validateReading coerces numbers, trims strings and reports errors', () => {
  const ok = M.validateReading({
    profileId: PROFILE, at: ' 2026-10-06T07:33 ', sys: '120', dia: 80, pulse: '71',
    feeling: 'Good', body: 'Sitting', arm: 'Left Arm', note: '  after coffee  '
  })
  assert.equal(ok.ok, true, ok.errors.join('; '))
  assert.equal(ok.value.sys, 120)
  assert.equal(ok.value.pulse, 71)
  assert.equal(ok.value.at, '2026-10-06T07:33')
  assert.equal(ok.value.note, 'after coffee')
  assert.match(ok.value.id, /^r_[0-9a-f]{12}$/)

  const bad = M.validateReading({ profileId: 'nope', at: '2026-10-06', sys: 49, dia: 151, pulse: 220.5, feeling: 'Meh', body: 'Flying', arm: 'Both' })
  assert.equal(bad.ok, false)
  assert.ok(bad.errors.length >= 7, bad.errors.join('; '))

  const clamped = M.validateReading({ profileId: PROFILE, at: '2026-10-06T07:33', sys: 120, dia: 80, pulse: 70, note: 'x'.repeat(300) + '\u0007' })
  assert.equal(clamped.ok, true)
  assert.equal(clamped.value.note.length, 200)

  assert.equal(M.validateReading(null).ok, false)
  assert.equal(M.validateReading({ profileId: PROFILE, at: '2026-10-06T07:33', sys: 250, dia: 150, pulse: 30 }).ok, true)
  assert.equal(M.validateReading({ profileId: PROFILE, at: '2026-10-06T07:33', sys: 251, dia: 150, pulse: 30 }).ok, false)
  assert.equal(M.validateReading({ profileId: PROFILE, at: '2026-10-06T07:33', sys: 120, dia: 29, pulse: 30 }).ok, false)
  assert.equal(M.validateReading({ profileId: PROFILE, at: '2026-10-06T07:33', sys: 120, dia: 80, pulse: 221 }).ok, false)
  assert.equal(M.validateReading({ profileId: PROFILE, at: '2026-10-06T07:33', sys: 'abc', dia: 80, pulse: 70 }).ok, false)
})

test('validateProfileName trims and bounds the name', () => {
  assert.deepEqual(M.validateProfileName('  Ana  ').value, 'Ana')
  assert.equal(M.validateProfileName('   ').ok, false)
  assert.equal(M.validateProfileName('x'.repeat(41)).ok, false)
  assert.equal(M.validateProfileName('x'.repeat(40)).ok, true)
  assert.equal(M.validateProfileName(42).ok, false)
})

test('newId and emptyState', () => {
  assert.match(M.newId('p'), /^p_[0-9a-f]{12}$/)
  assert.notEqual(M.newId('r'), M.newId('r'))
  assert.deepEqual(M.emptyState(), { version: 1, activeProfile: null, profiles: [], readings: [] })
})

test('validateState accepts a well-formed document and rejects caps and references', () => {
  const profile = { id: PROFILE, name: 'Ana', color: '#a855f7', createdAt: '2026-10-01T09:00' }
  const good = { version: 1, activeProfile: PROFILE, profiles: [profile], readings: [reading('2026-10-06T07:33', 120, 80, 70)], junk: true }
  const res = M.validateState(good)
  assert.equal(res.ok, true, res.errors.join('; '))
  assert.equal(res.state.junk, undefined)
  assert.equal(res.state.readings.length, 1)

  assert.equal(M.validateState(M.emptyState()).ok, true)
  assert.equal(M.validateState({ version: 2, activeProfile: null, profiles: [], readings: [] }).ok, false)
  assert.equal(M.validateState(null).ok, false)
  assert.equal(M.validateState({ version: 1, activeProfile: 'p_ffffffffffff', profiles: [], readings: [] }).ok, false)
  assert.equal(M.validateState({ version: 1, activeProfile: null, profiles: [], readings: [reading('2026-10-06T07:33', 120, 80, 70)] }).ok, false, 'orphan reading')

  const manyProfiles = []
  for (let i = 0; i < 21; i++) manyProfiles.push({ id: 'p_' + String(i).padStart(12, '0'), name: 'P' + i, color: '#a855f7', createdAt: '2026-10-01T09:00' })
  assert.equal(M.validateState({ version: 1, activeProfile: null, profiles: manyProfiles, readings: [] }).ok, false, 'profile cap')
  assert.equal(M.validateState({ version: 1, activeProfile: null, profiles: manyProfiles.slice(0, 20), readings: [] }).ok, true)

  const manyReadings = []
  for (let i = 0; i < 20001; i++) manyReadings.push({ id: 'r_' + i.toString(16).padStart(12, '0'), profileId: PROFILE, at: '2026-10-06T07:33', sys: 120, dia: 80, pulse: 70, feeling: '', body: '', arm: '', note: '' })
  assert.equal(M.validateState({ version: 1, activeProfile: null, profiles: [profile], readings: manyReadings }).ok, false, 'reading cap')
  assert.equal(M.validateState({ version: 1, activeProfile: null, profiles: [profile], readings: manyReadings.slice(0, 20000) }).ok, true)

  const longNote = reading('2026-10-06T07:33', 120, 80, 70, { note: 'x'.repeat(201) })
  assert.equal(M.validateState({ version: 1, activeProfile: null, profiles: [profile], readings: [longNote] }).ok, false, 'note cap is rejected, not truncated')
  const dupIds = [reading('2026-10-06T07:33', 120, 80, 70, { id: 'r_000000000001' }), reading('2026-10-06T08:33', 120, 80, 70, { id: 'r_000000000001' })]
  assert.equal(M.validateState({ version: 1, activeProfile: null, profiles: [profile], readings: dupIds }).ok, false, 'duplicate ids')
  assert.equal(M.validateState({ version: 1, activeProfile: null, profiles: [{ id: PROFILE, name: 'Ana', color: 'red', createdAt: '2026-10-01T09:00' }], readings: [] }).ok, false, 'colour shape')
  assert.equal(M.validateState({ version: 1, activeProfile: null, profiles: [profile], readings: [reading('2026-10-06T07:33', '120', 80, 70)] }).ok, false, 'state numbers are not coerced')
})

test('plain strips markup, control and bidi characters and caps length', () => {
  assert.equal(M.plain('<b>Ana</b> & co\u0007‮‏'), 'bAna/b  co')
  assert.equal(M.plain(null), '')
  assert.equal(M.plain(12345), '12345')
  assert.equal(M.plain('x'.repeat(500)).length, 200)
  assert.equal(M.plain('abcdef', 3), 'abc')
})

test('csvRows has the documented header and neutralises formula prefixes', () => {
  const rows = M.csvRows([reading('2026-10-06T07:33', 135, 85, 70, { feeling: 'Good', body: 'Sitting', arm: 'Left Arm', note: '=SUM(A1)' })])
  assert.deepEqual(rows[0], ['Date', 'Time', 'Systolic (mmHg)', 'Diastolic (mmHg)', 'Pulse (bpm)', 'Category', 'Feeling', 'Body', 'Arm', 'Note'])
  assert.deepEqual(rows[1], ['Oct 6, 2026', '7:33 AM', 135, 85, 70, 'Stage 1', 'Good', 'Sitting', 'Left Arm', "'=SUM(A1)"])
})

test('chartSeries exposes points and distinct day labels', () => {
  const s = M.chartSeries([
    reading('2026-10-05T07:00', 120, 80, 70),
    reading('2026-10-05T20:00', 121, 81, 71),
    reading('2026-10-06T07:00', 122, 82, 72)
  ])
  assert.equal(s.points.length, 3)
  assert.deepEqual(s.points[0], { t: new Date(2026, 9, 5, 7, 0).getTime(), sys: 120, dia: 80, pulse: 70 })
  assert.deepEqual(s.labels.map(l => l.label), ['Oct 5', 'Oct 6'])
  assert.equal(s.labels[0].t, new Date(2026, 9, 5).getTime())
  const many = []
  for (let i = 0; i < 20; i++) many.push({ t: i, label: 'd' + i })
  const thinned = M.thinLabels(many, 8)
  assert.ok(thinned.length <= 8 && thinned.length >= 7, String(thinned.length))
  assert.equal(thinned[0].label, 'd0')
})

test('initialColor cycles through a fixed palette starting with purple', () => {
  assert.equal(M.initialColor(0), '#a855f7')
  assert.equal(M.PALETTE.length, 8)
  assert.equal(M.initialColor(8), M.initialColor(0))
  assert.equal(M.profileInitial('ana'), 'A')
  assert.equal(M.profileInitial('   '), '?')
})

test('lastReading returns the most recent reading of one profile', () => {
  const rs = [
    reading('2026-10-05T07:00', 120, 80, 70),
    reading('2026-10-06T08:00', 129, 83, 72),
    reading('2026-10-06T09:00', 150, 95, 80, { profileId: OTHER }),
    reading('2026-10-04T23:00', 110, 70, 60)
  ]
  assert.equal(M.lastReading(rs, PROFILE).sys, 129)
  assert.equal(M.lastReading(rs, OTHER).sys, 150)
  assert.equal(M.lastReading(rs, 'p_000000000000'), null)
  assert.equal(M.lastReading([], PROFILE), null)
  assert.equal(M.lastReading(null, PROFILE), null)
})

test('downsample keeps at most max points including first and last', () => {
  const pts = []
  for (let i = 0; i < 1000; i++) pts.push({ t: i })
  const out = M.downsample(pts, 400)
  assert.ok(out.length <= 400, String(out.length))
  assert.ok(out.length >= 399, String(out.length))
  assert.equal(out[0].t, 0)
  assert.equal(out[out.length - 1].t, 999)
  for (let i = 1; i < out.length; i++) assert.ok(out[i].t > out[i - 1].t)
  assert.equal(M.downsample(pts.slice(0, 10), 400).length, 10)
  assert.deepEqual(M.downsample([], 400), [])
  assert.equal(M.downsample(pts, 1).length, 1)
})

test('splitAt and joinAt round-trip date and time fields', () => {
  assert.deepEqual(M.splitAt('2026-10-06T09:05'), { date: '2026-10-06', time: '09:05' })
  assert.deepEqual(M.splitAt('garbage'), { date: '', time: '' })
  assert.equal(M.joinAt('2026-10-06', '09:05'), '2026-10-06T09:05')
  assert.equal(M.joinAt(' 2026-10-06 ', '9:05'), '2026-10-06T09:05')
  assert.equal(M.joinAt('2026-02-30', '09:05'), null)
  assert.equal(M.joinAt('2026-10-06', '24:00'), null)
  assert.equal(M.joinAt('2026-10-6', '09:05'), null)
  assert.equal(M.joinAt(null, '09:05'), null)
})

test('isExportPath accepts only helper-shaped absolute export paths', () => {
  assert.ok(M.isExportPath('/home/u/Documents/Tensio/Tensio-Ana-20261006-0900.pdf'))
  assert.ok(M.isExportPath('/home/u/Documents/Tensio/Tensio-Ana-20261006-0900-2.csv'))
  assert.ok(!M.isExportPath('relative/Tensio/Tensio-a.pdf'))
  assert.ok(!M.isExportPath('/home/u/Documents/Tensio/Tensio-a.sh'))
  assert.ok(!M.isExportPath('/home/u/Documents/Other/report.pdf'))
  assert.ok(!M.isExportPath('/home/u/Documents/Tensio/Tensio-a\n.pdf'))
  assert.ok(!M.isExportPath('/home/u/../etc/Tensio/Tensio-a.pdf'))
  assert.ok(!M.isExportPath(42))
  assert.ok(!M.isExportPath('/' + 'a'.repeat(5000) + '/Tensio/Tensio-a.pdf'))
  assert.equal(M.exportFolder('/home/u/Documents/Tensio/Tensio-Ana-1.pdf'), '/home/u/Documents/Tensio')
  assert.equal(M.exportFolder('/etc/passwd'), '')
})

test('readingLine formats a compact reading summary', () => {
  assert.equal(M.readingLine({ sys: 129, dia: 83 }), '129/83')
  assert.equal(M.readingLine(null), '')
})

console.log('ok ' + passed + ' test groups')
