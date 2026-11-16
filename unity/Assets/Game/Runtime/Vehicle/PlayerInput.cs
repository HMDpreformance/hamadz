using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Player controls: on-screen touch pedals and steering (set by the HUD buttons), or keyboard /
    /// gamepad on PC. Steering on touch eases in and centres itself like the Godot game did.
    /// </summary>
    public class PlayerInput : MonoBehaviour
    {
        public static bool TouchLeft, TouchRight, TouchGas, TouchBrake, TouchNitro, TouchHandbrake;
        CarController car;
        float steer;

        void Start() => car = GetComponent<CarController>();

        void Update()
        {
            if (car == null) return;
            float kSteer = Input.GetAxisRaw("Horizontal");
            float kGas = Input.GetKey(KeyCode.W) || Input.GetKey(KeyCode.UpArrow) ? 1 : 0;
            float kBrake = Input.GetKey(KeyCode.S) || Input.GetKey(KeyCode.DownArrow) ? 1 : 0;
            bool kHand = Input.GetKey(KeyCode.Space);
            bool kNitro = Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.N);

            float target = kSteer;
            if (TouchLeft) target -= 1;
            if (TouchRight) target += 1;
            target = Mathf.Clamp(target, -1, 1);
            // ease in, snap back faster (feels natural on buttons)
            float rate = Mathf.Abs(target) > Mathf.Abs(steer) && Mathf.Sign(target) == Mathf.Sign(steer) ? 3.2f : 6f;
            steer = Mathf.MoveTowards(steer, target, rate * Time.deltaTime);

            car.steer = steer;
            car.throttle = Mathf.Max(kGas, TouchGas ? 1 : 0);
            car.brake = Mathf.Max(kBrake, TouchBrake ? 1 : 0);
            car.handbrake = kHand || TouchHandbrake;
            car.nitro = kNitro || TouchNitro;
        }
    }
}
