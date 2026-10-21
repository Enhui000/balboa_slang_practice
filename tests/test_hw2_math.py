"""Regression checks for coordinate changes and raw-parameter animation."""
import unittest
import numpy as np
from hw2.hw2_scene import compose_transformations
from hw2.hw2 import screen_matrices, interpolate_transformation

class TransformTests(unittest.TestCase):
    def test_lookat_inverse_and_forward_axis(self):
        p=np.array([2.,3.,5.]); target=np.array([-1.,2.,0.])
        L=compose_transformations([{'lookat':{'position':p,'target':target,'up':[0,1,0]}}])
        np.testing.assert_allclose(L@np.array([0,0,0,1]),[*p,1],atol=1e-6)
        d=(target-p)/np.linalg.norm(target-p)
        np.testing.assert_allclose(L@np.array([0,0,-1,1]),[*(p+d),1],atol=1e-6)
        np.testing.assert_allclose(np.linalg.inv(L)@np.array([*p,1]),[0,0,0,1],atol=1e-6)
    def test_order_and_normal_transform(self):
        M=compose_transformations([{'scale':[2,1,3]},{'rotate_y':[37]},{'translate':[1,2,3]}])
        np.testing.assert_allclose(M[:3,3],[1,2,3])
        tangent=np.array([1.,-1.,0.]); normal=np.array([1.,1.,0.])
        self.assertAlmostEqual(float(np.dot(M[:3,:3]@tangent,np.linalg.inv(M[:3,:3]).T@normal)),0,places=6)
    def test_screen_projection(self):
        P,S=screen_matrices(800,600,.5)
        q=S@P@np.array([1.,.5,-4.,1.]); q=q[:3]/q[3]
        np.testing.assert_allclose(q,[550,225,.25],atol=1e-5)
    def test_full_turn_and_keyframe_clamps(self):
        keys=[{'time':0,'transform':[{'rotate_y':[0]}]}, {'time':10,'transform':[{'rotate_y':[360]}]}]
        self.assertEqual(interpolate_transformation(keys,5),[{'rotate_y':[180.]}])
        self.assertEqual(interpolate_transformation(keys,-1),keys[0]['transform'])
        self.assertEqual(interpolate_transformation(keys,20),keys[1]['transform'])
    def test_invalid_camera(self):
        with self.assertRaises(ValueError):
            compose_transformations([{'lookat':{'position':[0,0,0],'target':[0,0,0],'up':[0,1,0]}}])

if __name__=='__main__': unittest.main()
