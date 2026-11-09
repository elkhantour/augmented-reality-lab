using UnityEngine;
using UnityEngine.Events;
using UnityEngine.EventSystems;

/// Put this on each map pointer. Taps open the dialog.
/// Facing the camera is handled by the Custom/MapPointerBillboard shader when the material uses it;
/// otherwise this script rotates the object itself.
[RequireComponent(typeof(Collider))]
public class MapPointer : MonoBehaviour, IPointerClickHandler
{
    const string BillboardShaderName = "Custom/MapPointerBillboard";

    [Header("Content")]
    public MapPointData data;

    [Header("Script billboard (ignored automatically when the billboard shader is used)")]
    public bool faceCamera = true;
    [Tooltip("On: stays upright and only turns left/right. Off: fully copies the camera rotation.")]
    public bool yawOnly = true;
    [Tooltip("Unity Quad: (0,0,0)   Unity Plane: (-90,0,0)   If it shows mirrored or backwards, add 180 on Y.")]
    public Vector3 rotationOffset = Vector3.zero;
    [Tooltip("Leave empty to use Camera.main (the AR camera).")]
    public Camera referenceCamera;

    [Header("Tap area (billboard shader + SphereCollider)")]
    [Tooltip("Keeps the SphereCollider matching the drawn icon, including Constant Screen Size.")]
    public bool syncColliderToVisual = true;
    [Min(0.1f)] public float tapAreaScale = 1.2f;

    [Header("Events")]
    public UnityEvent onTapped;

    Renderer rend;
    Collider col;
    SphereCollider sphere;
    bool usesShaderBillboard;
    bool checkMask; // true when the material has "Hide Outside City Mask" ticked
    bool raycasterChecked;

    Camera GetCamera() => referenceCamera != null ? referenceCamera : Camera.main;

    void Awake()
    {
        rend = GetComponent<Renderer>();
        col = GetComponent<Collider>();
        sphere = GetComponent<SphereCollider>();
        usesShaderBillboard = IsBillboardMaterial(rend);
        checkMask = usesShaderBillboard && rend.sharedMaterial.IsKeywordEnabled("_USE_CITY_MASK");
    }

    static bool IsBillboardMaterial(Renderer r)
    {
        return r != null && r.sharedMaterial != null && r.sharedMaterial.shader != null
            && r.sharedMaterial.shader.name == BillboardShaderName;
    }

    void OnValidate()
    {
        if (IsBillboardMaterial(GetComponent<Renderer>()) && !(GetComponent<Collider>() is SphereCollider))
            Debug.LogWarning("MapPointer: with the billboard shader, use a SphereCollider. " +
                             "Other colliders don't follow the shader's rotation, so taps would miss the icon.", this);
    }

    void Start() => EnsureRaycaster();

    // Taps reach this object through the EventSystem, which needs a PhysicsRaycaster on the camera
    void EnsureRaycaster()
    {
        if (raycasterChecked) return;
        Camera c = GetCamera();
        if (c == null) return;

        if (c.GetComponent<PhysicsRaycaster>() == null)
            c.gameObject.AddComponent<PhysicsRaycaster>();

        raycasterChecked = true;
    }

    void LateUpdate()
    {
        Camera c = GetCamera();
        if (c == null) return;
        EnsureRaycaster();

        if (usesShaderBillboard)
        {
            // Pointer hidden by the city mask -> also untappable, so taps pass through it
            if (checkMask && col != null)
                col.enabled = CityClipController.IsInside(transform.position);

            if (syncColliderToVisual) SyncCollider(c);
            return; // the shader already faces the camera
        }

        if (!faceCamera) return;

        Quaternion offset = Quaternion.Euler(rotationOffset);

        if (yawOnly)
        {
            Vector3 away = transform.position - c.transform.position;
            away.y = 0f;
            if (away.sqrMagnitude < 1e-6f) return;
            transform.rotation = Quaternion.LookRotation(away.normalized, Vector3.up) * offset;
        }
        else
        {
            transform.rotation = c.transform.rotation * offset;
        }
    }

    // Mirrors the shader's size/anchor math so the tap area stays on the visible icon
    void SyncCollider(Camera c)
    {
        if (sphere == null) return;

        Material m = rend.sharedMaterial;
        Vector3 s = transform.lossyScale;
        float w = s.x;
        float h = s.y;

        if (m.GetFloat("_ConstantSize") > 0.5f)
        {
            float dist = Vector3.Distance(c.transform.position, transform.position);
            h = m.GetFloat("_ScreenHeight") * 2f * dist / c.projectionMatrix.m11;
            w = h * s.x / Mathf.Max(s.y, 1e-5f);
        }

        float maxScale = Mathf.Max(s.x, Mathf.Max(s.y, s.z));
        sphere.radius = 0.5f * Mathf.Max(w, h) * tapAreaScale / Mathf.Max(maxScale, 1e-5f);

        // Move the sphere onto the icon (matters when Anchor Y is not 0)
        Vector3 up = m.GetFloat("_YawOnly") > 0.5f ? Vector3.up : c.transform.up;
        sphere.center = transform.InverseTransformVector(up * m.GetFloat("_AnchorY") * h);
    }

    // Fires on a clean tap, not when the finger drags (so AR gestures don't open it)
    public void OnPointerClick(PointerEventData eventData) => Open();

    public void Open()
    {
        onTapped?.Invoke();

        if (data == null)
        {
            Debug.LogWarning($"MapPointer '{name}' has no MapPointData assigned.", this);
            return;
        }

        if (MapPointDialog.Instance == null)
        {
            Debug.LogWarning("No MapPointDialog found in the scene.", this);
            return;
        }

        MapPointDialog.Instance.Show(data);
    }

    /// Useful when pointers are spawned at runtime
    public void SetData(MapPointData newData) => data = newData;
}
