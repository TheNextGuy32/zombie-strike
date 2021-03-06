import { CollectionService, ReplicatedStorage, SoundService } from "@rbxts/services"
import * as BossLocalScriptUtil from "mission/ReplicatedStorage/Libraries/BossLocalScriptUtil"
import PlayQuickSound from "shared/ReplicatedStorage/Core/PlayQuickSound"

const PROJECTILE_Y = 3 // ooohh god
const RANDOM_RANGE = 25

const SwordBeamAttack = BossLocalScriptUtil.WaitForBossRemote("SwordBeamAttack")

SwordBeamAttack.OnClientEvent.Connect((point: Vector2int16) => {
	const boss = CollectionService.GetTagged("Boss")[0] as Model

	const initial = new Vector3(boss.PrimaryPart!.Position.X, PROJECTILE_Y, boss.PrimaryPart!.Position.Z)
	const characterPoint = new Vector3(point.X, PROJECTILE_Y, point.Y)
	const unit = characterPoint.sub(initial).Unit

	PlayQuickSound(
		SoundService.ZombieSounds.Samurai.Boss.Attack,
		BossLocalScriptUtil.Projectile(
			ReplicatedStorage.Assets.Bosses.Samurai.Boss.Crescent,
			{
				initial,
				lifetime: 3,
				goal: characterPoint.add(unit.mul(characterPoint.Magnitude)).add(
					new Vector3(
						math.random(-RANDOM_RANGE, RANDOM_RANGE),
						0,
						math.random(-RANDOM_RANGE, RANDOM_RANGE),
					),
				),
				speed: 90,
				onTouched: SwordBeamAttack,
			},
		),
	)
})
