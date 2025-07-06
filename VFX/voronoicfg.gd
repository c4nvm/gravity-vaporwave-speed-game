extends VoronoiGeneratorConfig

func _ready():
	var rng = RandomNumberGenerator.new()
	random_seed = rng.randi()
	num_samples = 32
