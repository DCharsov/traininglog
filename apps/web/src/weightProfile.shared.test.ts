import { expect, it } from 'vitest'
import { equipmentSchema } from './domain'
import cases from '../../watch/WorkoutCore/Sources/WorkoutCore/Resources/weight-profile-cases.json'

const equipment = { id: '11111111-1111-4111-8111-111111111111', name: 'Test', mode: 'MachineStack' }
for (const c of cases) it(`shared Swift weight profile: ${c.name}`, () => {
 expect(equipmentSchema.safeParse({...equipment, ...c.profile}).success).toBe(c.valid)
})
it('profile allows at most 200 weights', () => {
 for (const size of [200, 201]) expect(equipmentSchema.safeParse({...equipment, availableGrams: Array(size).fill(1000)}).success).toBe(size === 200)
})
