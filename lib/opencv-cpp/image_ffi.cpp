#include <iostream>
#include <vector>
#include <opencv2/opencv.hpp>

void image_ffi(uchar *buf, uint *size, uchar *res, double kp)
{
    std::vector<uchar> v(buf, buf + size[0]);
    cv::Mat img = cv::imdecode(cv::Mat(v), cv::IMREAD_COLOR);

    cv::Mat processed;
    cv::GaussianBlur(img, processed, cv::Size(15, 15), 0, 0);
    cv::cvtColor(processed, processed, cv::COLOR_BGR2HSV);
    cv::inRange(processed, cv::Scalar(29, 89, 6), cv::Scalar(64, 255, 255), processed);
    cv::erode(processed, processed, cv::Mat(), cv::Point(-1, -1), 2);
    cv::dilate(processed, processed, cv::Mat(), cv::Point(-1, -1), 2);

    std::vector<std::vector<cv::Point>> contours;
    std::vector<cv::Vec4i> hierarchy;
    cv::findContours(processed, contours, hierarchy, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    cv::Point center;
    uint8_t ena = 0, enb = 0;

    if (contours.size() > 0)
    {
        std::vector<cv::Point> largestContour = *max_element(contours.begin(), contours.end(), [](const std::vector<cv::Point> &a, const std::vector<cv::Point> &b)
                                                             { return cv::contourArea(a) < cv::contourArea(b); });
        // Compute the minimum enclosing circle and centroid
        cv::Point2f centerF;
        float radius;
        minEnclosingCircle(largestContour, centerF, radius);

        cv::Moments M = moments(largestContour);
        center = cv::Point(static_cast<int>(M.m10 / M.m00), static_cast<int>(M.m01 / M.m00));

        // Only proceed if the radius meets a minimum size
        if (radius > 10)
        {
            // Draw the circle and centroid on the frame
            cv::circle(img, centerF, static_cast<int>(radius), cv::Scalar(0, 255, 255), 2);
            cv::circle(img, center, 5, cv::Scalar(0, 0, 255), -1);
            int w = img.cols;
            if (center.x != -1)
            {
                float error = center.x - w/2.0;
                float pOut = kp*std::abs(error);
                float out = pOut/(w/2.0)*255;
                if (error > 20)
                {
                    cv::putText(img, "right", cv::Point(50, 50), cv::FONT_HERSHEY_SIMPLEX, 1, cv::Scalar(0, 255, 0), 2, cv::LINE_4);
                    ena = 255;
                    enb = 255 - out;
                }
                else if (error < -20)
                {
                    cv::putText(img, "left", cv::Point(50, 50), cv::FONT_HERSHEY_SIMPLEX, 1, cv::Scalar(0, 255, 0), 2, cv::LINE_4);
                    enb = 255;
                    ena = 255 - out;
                }
                else
                {
                    cv::putText(img, "forward", cv::Point(50, 50), cv::FONT_HERSHEY_SIMPLEX, 1, cv::Scalar(0, 255, 255), 2, cv::LINE_4);
                    ena = 255;
                    enb = 255;
                }

            } else {
                ena = 0;
                enb = 0;
            }
        }
    }
    // cv::putText(img, "Hello World!", cv::Size(30, 30), 1, 1.5, 2, 2);

    std::vector<uchar> retv;
    cv::imencode(".jpg", img, retv);
    memcpy(buf, retv.data(), retv.size());
    size[0] = retv.size();
    res[0] = ena;
    res[1] = enb;
}