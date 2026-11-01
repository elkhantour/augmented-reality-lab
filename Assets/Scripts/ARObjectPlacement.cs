using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.ARSubsystems;

public class ARObjectPlacement : MonoBehaviour
{
    [SerializeField]
    private ARRaycastManager raycastManager;

    [SerializeField]
    private GameObject prefab;

    private static readonly
        System.Collections.Generic.List<ARRaycastHit>
        hits = new();

    void Update()
    {
        if (Touchscreen.current == null)
            return;

        if (!Touchscreen.current.primaryTouch
            .press.wasPressedThisFrame)
            return;

        Vector2 touchPosition =
            Touchscreen.current.primaryTouch.position.ReadValue();

        if (raycastManager.Raycast(
            touchPosition,
            hits,
            TrackableType.PlaneWithinPolygon))
        {
            Pose pose = hits[0].pose;

            Instantiate(
                prefab,
                pose.position,
                pose.rotation
            );
        }
    }
}
