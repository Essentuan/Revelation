vec3 ScreenToViewPosRaw(in vec3 screenPos) {
	vec3 ndcPos = screenPos * 2.0 - 1.0;
	return ProjectDivide(ndcPos, gbufferProjectionInverse);
}

vec3 ScreenToViewPos(in vec3 screenPos) {
	vec3 ndcPos = screenPos * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		ndcPos.xy -= taaJitter;
	#endif
	return ProjectDivide(ndcPos, gbufferProjectionInverse);
}

vec3 ScreenToViewPosRaw(in vec2 screenPos, in float viewDepth) {
	vec2 ndcPos = screenPos * 2.0 - 1.0;
	return vec3(diagonal2(gbufferProjectionInverse) * ndcPos * -viewDepth, viewDepth);
}

vec3 ScreenToViewPos(in vec2 screenPos, in float viewDepth) {
	vec2 ndcPos = screenPos * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		ndcPos -= taaJitter;
	#endif
	return vec3(diagonal2(gbufferProjectionInverse) * ndcPos * -viewDepth, viewDepth);
}

vec3 ScreenToViewPos(in vec2 screenPos) {
	vec3 ndcPos = vec3(screenPos, loadDepth0(uvToTexel(screenPos))) * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		ndcPos.xy -= taaJitter;
	#endif
	return ProjectDivide(ndcPos, gbufferProjectionInverse);
}

vec3 ViewToScreenPosRaw(in vec3 viewPos) {
	vec3 ndcPos = projMAD(gbufferProjection, viewPos) * rcp(-viewPos.z);

	return ndcPos * 0.5 + 0.5;
}

vec3 ViewToScreenPos(in vec3 viewPos) {
	vec3 ndcPos = projMAD(gbufferProjection, viewPos) * rcp(-viewPos.z);
	#ifdef TAA_ENABLED
		ndcPos.xy += taaJitter;
	#endif
	return ndcPos * 0.5 + 0.5;
}

vec3 ScreenToViewDirRaw(in vec2 screenPos) {
	vec2 ndcPos = screenPos * 2.0 - 1.0;
	return normalize(vec3(diagonal2(gbufferProjectionInverse) * ndcPos, gbufferProjectionInverse[3].z));
}

vec3 ScreenToViewDir(in vec2 screenPos) {
	vec2 ndcPos = screenPos * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		ndcPos -= taaJitter;
	#endif
	return normalize(vec3(diagonal2(gbufferProjectionInverse) * ndcPos, gbufferProjectionInverse[3].z));
}

vec3 ReprojectScreenPos(in vec3 screenPos) {
	vec3 position = ScreenToViewPosRaw(screenPos); // To view
    position = transMAD(gbufferModelViewInverse, position); // To world

	position += cameraMovement * step(0.56, screenPos.z); // To previous world
    position = transMAD(gbufferPreviousModelView, position); // To previous view
	position = projMAD(gbufferPreviousProjection, position) * rcp(-position.z); // To previous NDC

    return position * 0.5 + 0.5;
}

float ScreenToViewDepth(in float depth) {
	return -gbufferProjection[3].z / (gbufferProjection[2].z + (depth * 2.0 - 1.0));
}

float ViewToScreenDepth(in float depth) {
	return 0.5 - (gbufferProjection[3].z / depth + gbufferProjection[2].z) * 0.5;
}

//================================================================================================//

#if defined LOD_MOD
	vec3 ScreenToViewPosRawLod(in vec3 screenPos) {
		vec3 ndcPos = screenPos * 2.0 - 1.0;
		return ProjectDivide(ndcPos, lodProjectionInv);
	}

	vec3 ScreenToViewPosLod(in vec3 screenPos) {
		vec3 ndcPos = screenPos * 2.0 - 1.0;
		#ifdef TAA_ENABLED
			ndcPos.xy -= taaJitter;
		#endif
		return ProjectDivide(ndcPos, lodProjectionInv);
	}

	vec3 ScreenToViewPosLod(in vec2 screenPos) {
		vec3 ndcPos = vec3(screenPos, loadDepth0Lod(uvToTexel(screenPos))) * 2.0 - 1.0;
		#ifdef TAA_ENABLED
			ndcPos.xy -= taaJitter;
		#endif
		return ProjectDivide(ndcPos, lodProjectionInv);
	}

	vec3 ViewToScreenPosRawLod(in vec3 viewPos) {
		vec3 ndcPos = projMAD(lodProjection, viewPos) * rcp(-viewPos.z);

		return ndcPos * 0.5 + 0.5;
	}

	vec3 ViewToScreenPosLod(in vec3 viewPos) {
		vec3 ndcPos = projMAD(lodProjection, viewPos) * rcp(-viewPos.z);
		#ifdef TAA_ENABLED
			ndcPos.xy += taaJitter;
		#endif
		return ndcPos * 0.5 + 0.5;
	}

	vec3 ReprojectScreenPosLod(in vec3 screenPos) {
		vec3 position = ScreenToViewPosRawLod(screenPos); // To view
		position = transMAD(gbufferModelViewInverse, position); // To world

		position += cameraMovement/*  * step(0.56, screenPos.z) */; // To previous world
		position = transMAD(gbufferPreviousModelView, position); // To previous view
		position = projMAD(lodPrevProjection, position) * rcp(-position.z); // To previous NDC

		return position * 0.5 + 0.5;
	}

	float ScreenToViewDepthLod(in float depth) {
		return -lodProjection[3].z / (lodProjection[2].z + (depth * 2.0 - 1.0));
	}

	float ViewToScreenDepthLod(in float depth) {
		return 0.5 - (lodProjection[3].z / depth + lodProjection[2].z) * 0.5;
	}
#endif
