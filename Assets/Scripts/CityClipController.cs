using UnityEngine;

[ExecuteAlways]
public class CityClipController : MonoBehaviour
{
    [Header("Killswitch")]
    [Tooltip("Untick to show the whole city with no clipping and no glow.")]
    public bool maskEnabled = true;

    [Header("Shape")]
    public Transform cityRoot; // optional: mask follows this (useful in AR)
    public Vector2 halfSize = new Vector2(30f, 30f);
    [Min(0)] public float cornerRadius = 4f;

    [Header("Wave")]
    public float waveAmplitude = 1.5f;
    public float waveFrequency = 0.15f;
    public float waveSpeed = 0.6f;

    [Header("Edge glow")]
    public float edgeWidth = 1.2f;
    [ColorUsage(true, true)] public Color edgeColor = new Color(0.3f, 0.8f, 2.5f);
    public float edgeIntensity = 2f;

    /// Call from code or a UI Toggle to switch the mask on or off at runtime.
    public void SetMaskEnabled(bool value) => maskEnabled = value;

    void OnEnable() => Apply();

    // Disabling the component or its GameObject also removes the mask
    void OnDisable() => Release();

    void Update() => Apply();

    void Apply()
    {
        if (!maskEnabled)
        {
            Release();
            return;
        }

        Vector3 center = cityRoot != null ? cityRoot.position : transform.position;

        Shader.SetGlobalVector("_MagicCenter", center);
        Shader.SetGlobalVector("_MagicHalfSize", halfSize);
        Shader.SetGlobalFloat("_MagicCorner", cornerRadius);
        Shader.SetGlobalFloat("_MagicWaveAmp", waveAmplitude);
        Shader.SetGlobalFloat("_MagicWaveFreq", waveFrequency);
        Shader.SetGlobalFloat("_MagicWaveSpeed", waveSpeed);
        Shader.SetGlobalFloat("_MagicEdgeWidth", edgeWidth);
        Shader.SetGlobalColor("_MagicEdgeColor", edgeColor);
        Shader.SetGlobalFloat("_MagicEdgeIntensity", edgeIntensity);
    }

    // Makes the visible area enormous and the glow zero, so nothing gets clipped.
    // Works with the shader as-is, no shader edit needed.
    static void Release()
    {
        Shader.SetGlobalVector("_MagicHalfSize", new Vector4(100000f, 100000f, 0f, 0f));
        Shader.SetGlobalFloat("_MagicEdgeIntensity", 0f);
    }

    void OnDrawGizmosSelected()
    {
        if (!maskEnabled) return;
        Vector3 c = cityRoot != null ? cityRoot.position : transform.position;
        Gizmos.color = Color.cyan;
        Gizmos.DrawWireCube(c, new Vector3(halfSize.x * 2, 0.1f, halfSize.y * 2));
    }
}
