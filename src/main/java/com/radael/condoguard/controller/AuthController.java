/*
 * This file is part of CondoGuard.
 *
 * CondoGuard is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * CondoGuard is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with CondoGuard. If not, see <https://www.gnu.org/licenses/>.
 */

package com.radael.condoguard.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;

import com.radael.condoguard.dto.AuthRequest;
import com.radael.condoguard.model.User;
import com.radael.condoguard.repository.UserRepository;
import com.radael.condoguard.security.JwtUtil;

import java.util.Map;
import java.util.HashMap;

@RestController
@RequestMapping("/auth")
public class AuthController {

    @Autowired
    private AuthenticationManager authenticationManager;

    @Autowired
    private JwtUtil jwtUtil;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private UserRepository userRepository;

    @PostMapping("/register")
    public ResponseEntity<Map<String, String>> registerUser(@RequestBody User user) {
        // Codifica a senha antes de salvar o usuário
        user.setPassword(passwordEncoder.encode(user.getPassword()));
        userRepository.save(user);

        // Cria o corpo da resposta
        Map<String, String> response = new HashMap<>();
        response.put("message", "User registered successfully!");

        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PostMapping("/login")
    public ResponseEntity<Map<String, Object>> login(@RequestBody AuthRequest authRequest) {
        try {
            // O AuthenticationManager tenta autenticar as credenciais fornecidas
            authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(authRequest.getUsername(), authRequest.getPassword())
            );
        } catch (UsernameNotFoundException | BadCredentialsException e) {
            // Captura exceções quando o usuário não é encontrado ou as credenciais estão incorretas
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", "Incorrect username or password");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(errorResponse);
        } catch (AuthenticationException e) {
            // Captura todas as outras exceções de autenticação
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", "Authentication failed");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(errorResponse);
        }

        // Fetch the user from the repository
        User user = userRepository.findByUsername(authRequest.getUsername());
        if (user == null) {
            throw new UsernameNotFoundException("User not found");
        }

        // Generate JWT token
        String token = jwtUtil.generateToken(user.getUsername());

        // Create the response body
        Map<String, Object> response = new HashMap<>();
        response.put("token", token);
        response.put("roles", user.getRoles());
        return ResponseEntity.ok(response);
    }
}

