-- Props used in more than one area of the map.

local Kit = require("./Kit")
local P = require("./Palette")

local Color3 = Kit.Color3

local Props = {}

-- Shopping cart standing on height `ground`, pointing along X or Z.
function Props.cart(k, parent, x, z, alongX, ground)
	ground = ground or 0
	local model = k:model(parent, "ShoppingCart")
	local sx, sz = 2.2, 3.6
	if alongX then
		sx, sz = sz, sx
	end
	k:span(
		model,
		"Basket",
		x - sx / 2,
		ground + 1.3,
		z - sz / 2,
		x + sx / 2,
		ground + 3.1,
		z + sz / 2,
		P.steel
	)
	k:span(
		model,
		"Frame",
		x - sx / 2 + 0.2,
		ground + 0.5,
		z - sz / 2 + 0.2,
		x + sx / 2 - 0.2,
		ground + 0.7,
		z + sz / 2 - 0.2,
		P.dDarkSteel
	)
	if alongX then
		k:span(
			model,
			"Handle",
			x + sx / 2,
			ground + 3.2,
			z - sz / 2,
			x + sx / 2 + 0.3,
			ground + 3.4,
			z + sz / 2,
			P.dRed
		)
	else
		k:span(
			model,
			"Handle",
			x - sx / 2,
			ground + 3.2,
			z + sz / 2,
			x + sx / 2,
			ground + 3.4,
			z + sz / 2 + 0.3,
			P.dRed
		)
	end
	for _, wx in { x - sx / 2 + 0.4, x + sx / 2 - 0.4 } do
		for _, wz in { z - sz / 2 + 0.4, z + sz / 2 - 0.4 } do
			k:cyl(model, "Wheel", wx, ground, wz, 0.5, 0.2, P.dBlack, "x")
		end
	end
	return model
end

-- Parked car, nose towards -Z when `facingNorth`, standing on height `ground`.
function Props.car(k, parent, x, z, facingNorth, ground)
	local model = k:model(parent, "ParkedCar")
	local paint = Kit.style(0, 0, 0, "SmoothPlastic")
	paint.color = Color3.fromHSV(k:rand(), k:range(0.05, 0.5), k:range(0.2, 0.6))
	local nose = if facingNorth then -1 else 1

	k:span(model, "Body", x - 3.5, ground + 1.1, z - 8, x + 3.5, ground + 3.4, z + 8, paint)
	k:span(
		model,
		"Cabin",
		x - 3.1,
		ground + 3.4,
		z - 3.5 - nose * 0.8,
		x + 3.1,
		ground + 5.4,
		z + 3.5 - nose * 0.8,
		Kit.style(20, 24, 30, "SmoothPlastic")
	)
	for _, wx in { x - 3.2, x + 3.2 } do
		for _, wz in { z - 5.2, z + 5.2 } do
			k:cyl(model, "Wheel", wx, ground, wz, 2.6, 1, P.dBlack, "x")
		end
	end
	for _, lx in { x - 2.9, x + 1.9 } do
		k:span(
			model,
			"Headlight",
			lx,
			ground + 2.2,
			z + nose * 8,
			lx + 1,
			ground + 2.8,
			z + nose * 8.05,
			Kit.decor(Kit.style(210, 214, 200, "Glass"))
		)
		k:span(
			model,
			"TailLight",
			lx,
			ground + 2.4,
			z - nose * 8,
			lx + 1,
			ground + 2.9,
			z - nose * 8.05,
			Kit.decor(Kit.style(120, 20, 20, "Glass"))
		)
	end
	return model
end

return Props
