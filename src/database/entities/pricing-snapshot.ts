import type { VehicleType } from './enums.js';

/**
 * Everything used to price one passenger, stored as JSONB on ride_passengers and
 * join_requests, so a dispute can be reproduced after the admin edits the fare rule.
 * Amounts are paisa; distances are metres.
 *
 *   soloFarePaisa = basePaisa + round(perKmPaisa * max(distanceM - baseDistanceM, 0) / 1000)
 *   ceilingPaisa  = ceilingBasePaisa + round(ceilingPerKmPaisa * max(distanceM - baseDistanceM, 0) / 1000)
 *   farePaisa     = min(shared ? round(soloFarePaisa * (10000 - shareDiscountBps) / 10000) : soloFarePaisa,
 *                       ceilingPaisa)
 */
export interface PricingSnapshot {
  fareRuleId: number;
  vehicleType: VehicleType;
  distanceM: number;
  baseDistanceM: number;
  basePaisa: number;
  perKmPaisa: number;
  ceilingBasePaisa: number;
  ceilingPerKmPaisa: number;
  shared: boolean;
  shareDiscountBps: number;
  soloFarePaisa: number;
  farePaisa: number;
  ceilingPaisa: number;
}
