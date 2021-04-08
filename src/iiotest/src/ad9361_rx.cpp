/*
 * Copyright 2021 Miklos Maroti.
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this software; see the file COPYING.  If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street,
 * Boston, MA 02110-1301, USA.
 */

#include <iio.h>
#include <cassert>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <iomanip>
#include <iostream>

static bool stop = false;
static void handle_sig(int) { stop = true; }

int main(int argc, char** argv)
{
    signal(SIGINT, handle_sig);

    std::cout << "Creating IIO context" << std::endl;
    struct iio_context* context = NULL;
    if (argc == 1)
        context = iio_create_default_context();
    else if (argc == 2)
        context = iio_create_context_from_uri(argv[1]);
    assert(context != nullptr);

    std::cout << "Finding ad9361-phy device" << std::endl;
    struct iio_device* phydev = iio_context_find_device(context, "ad9361-phy");

    std::cout << "Finding ad9361-phy rx1 controll channel" << std::endl;
    struct iio_channel* chn = iio_device_find_channel(phydev, "voltage0", false);
    assert(chn != nullptr);

    std::cout << "Setting rx port to A_BALANCED" << std::endl;
    ssize_t ret = iio_channel_attr_write(chn, "rf_port_select", "A_BALANCED");
    assert(ret >= 0);

    std::cout << "Setting rx bandwidth to 5.0 MHz" << std::endl;
    ret = iio_channel_attr_write_longlong(chn, "rf_bandwidth", 5.0e6);
    assert(ret >= 0);

    std::cout << "Setting sampling frequency to 20.0 Msps" << std::endl;
    ret = iio_channel_attr_write_longlong(chn, "sampling_frequency", 20.0e6);
    assert(ret >= 0);

    std::cout << "Finding ad9361-phy rx local oscillator channel" << std::endl;
    chn = iio_device_find_channel(phydev, "altvoltage0", true);
    assert(chn != nullptr);

    std::cout << "Setting center frequency to 2.5 GHz" << std::endl;
    ret = iio_channel_attr_write_longlong(chn, "frequency", 2.5e9);
    assert(ret >= 0);
    (void)ret;

    std::cout << "Finding cf-ad9361-lpc device" << std::endl;
    struct iio_device* device = iio_context_find_device(context, "cf-ad9361-lpc");
    assert(device != nullptr);

    std::cout << "Finding cf-ad9361-lpc streaming channels" << std::endl;
    struct iio_channel* channel_i = iio_device_find_channel(device, "voltage0", false);
    struct iio_channel* channel_q = iio_device_find_channel(device, "voltage1", false);

    std::cout << "Enabling cf-ad9361-lpc streaming channels" << std::endl;
    iio_channel_enable(channel_i);
    iio_channel_enable(channel_q);

    std::cout << "Creating non-cyclic buffer" << std::endl;
    struct iio_buffer* buffer = iio_device_create_buffer(device, 1024 * 1024, false);
    assert(buffer != nullptr);

    std::chrono::time_point<std::chrono::system_clock> time1 =
        std::chrono::system_clock::now();

    std::cout << "Starting streaming (press CTRL+C to cancel)" << std::endl;
    while (!stop) {
        ssize_t nbytes_rx = iio_buffer_refill(buffer);
        if (nbytes_rx < 0) {
            std::cout << "Error refilling buffer" << std::endl;
            break;
        }

        int16_t m0 = 0.0f;
        int16_t m1 = 0.0f;
        int16_t m2 = 0.0f;
        int16_t m3 = 0.0f;

        int16_t* data = (int16_t*)iio_buffer_first(buffer, channel_i);
        int count = ((int16_t*)iio_buffer_end(buffer) - data) / 2;
        for (int i = 0; i < 2 * count; i += 4) {
            int16_t a0 = data[i + 0]; // I0
            int16_t a1 = data[i + 1]; // Q0
            int16_t a2 = data[i + 2]; // I1
            int16_t a3 = data[i + 3]; // Q1

            a0 = std::abs(a0);
            a1 = std::abs(a1);
            a2 = std::abs(a2);
            a3 = std::abs(a3);

            m0 = std::max(m0, a0);
            m1 = std::max(m1, a1);
            m2 = std::max(m2, a2);
            m3 = std::max(m3, a3);
        }

        int16_t ampl = std::max(std::max(m0, m1), std::max(m2, m3));

        std::chrono::time_point<std::chrono::system_clock> time2 =
            std::chrono::system_clock::now();

        float rate =
            (float)count /
            std::chrono::duration_cast<std::chrono::microseconds>(time2 - time1).count();
        time1 = time2;

        std::cout << "Received " << count << " samples, " << std::fixed
                  << std::setprecision(3) << rate << " msps, max amplitude " << ampl
                  << std::endl;
    }

    std::cout << "Destroying buffer" << std::endl;
    iio_buffer_destroy(buffer);

    std::cout << "Disabling cf-ad9361-lpc streaming channels" << std::endl;
    iio_channel_disable(channel_i);
    iio_channel_disable(channel_q);

    std::cout << "Destroying context" << std::endl;
    iio_context_destroy(context);

    return 0;
}
