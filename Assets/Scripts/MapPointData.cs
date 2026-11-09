using UnityEngine;

/// Content of one map pointer's dialog. Create assets with:
/// Right-click in Project > Create > City > Map Point Data
[CreateAssetMenu(fileName = "NewMapPoint", menuName = "City/Map Point Data")]
public class MapPointData : ScriptableObject
{
    public Sprite image;
    public string headline;
    [TextArea(4, 12)] public string body;

    // Add more fields here later (link URL, audio clip, category icon...)
    // and read them in MapPointDialog.Show().
}
